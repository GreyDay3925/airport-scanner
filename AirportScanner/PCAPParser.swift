import Foundation

enum PCAPError: Error, LocalizedError {
    case tooShort
    case invalidMagic
    case unsupportedLinkType(UInt32)
    case truncatedPacket

    var errorDescription: String? {
        switch self {
        case .tooShort:                   return "File is too short to be a valid pcap."
        case .invalidMagic:               return "Not a valid pcap file (bad magic number)."
        case .unsupportedLinkType(let t): return "Unsupported link type \(t). Only IEEE 802.11 (105) and Radiotap (127) are supported."
        case .truncatedPacket:            return "File ends mid-packet (truncated capture)."
        }
    }
}

// MARK: - 802.11 Constants

private enum FrameType: UInt8 {
    case management = 0
    case control    = 1
    case data       = 2
}

private enum ManagementSubtype: UInt8 {
    case associationRequest    = 0
    case associationResponse   = 1
    case reassociationRequest  = 2
    case reassociationResponse = 3
    case probeRequest          = 4
    case probeResponse         = 5
    case beacon                = 8
    case disassociation        = 10
    case authentication        = 11
    case deauthentication      = 12
    case action                = 13
}

struct PCAPParser {

    static func parse(url: URL) throws -> PCAPSummary {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parseData(data, url: url)
    }

    static func parseData(_ data: Data, url: URL) throws -> PCAPSummary {
        guard data.count >= 24 else { throw PCAPError.tooShort }

        var summary = PCAPSummary(fileURL: url)
        var offset = 0

        // --- Global header ---
        let magic = data.readUInt32LE(at: offset)
        guard magic == 0xa1b2c3d4 || magic == 0xd4c3b2a1 ||
              magic == 0xa1b23c4d || magic == 0x4d3cb2a1 else {
            throw PCAPError.invalidMagic
        }
        let swapBytes = (magic == 0xd4c3b2a1 || magic == 0x4d3cb2a1)
        offset += 4

        offset += 4   // version major + minor
        offset += 4   // thiszone
        offset += 4   // sigfigs
        offset += 4   // snaplen

        let networkRaw = swapBytes
            ? data.readUInt32BE(at: offset)
            : data.readUInt32LE(at: offset)
        offset += 4

        summary.linkType = LinkType(rawValue: networkRaw) ?? .unknown
        guard summary.linkType != .unknown else {
            throw PCAPError.unsupportedLinkType(networkRaw)
        }

        // --- Packet records ---
        while offset + 16 <= data.count {
            let tsSec  = swapBytes ? data.readUInt32BE(at: offset)     : data.readUInt32LE(at: offset)
            let tsUsec = swapBytes ? data.readUInt32BE(at: offset + 4) : data.readUInt32LE(at: offset + 4)
            let inclLen = swapBytes ? data.readUInt32BE(at: offset + 8)  : data.readUInt32LE(at: offset + 8)
            offset += 16

            guard offset + Int(inclLen) <= data.count else {
                summary.parseErrors += 1
                break
            }

            let packetData = data[offset ..< offset + Int(inclLen)]
            offset += Int(inclLen)
            summary.totalPackets += 1

            let ts = Date(timeIntervalSince1970: Double(tsSec) + Double(tsUsec) / 1_000_000)
            if summary.firstTimestamp == nil { summary.firstTimestamp = ts }
            summary.lastTimestamp = ts

            do {
                try parsePacket(packetData, linkType: summary.linkType, into: &summary)
                summary.parsedPackets += 1
            } catch {
                summary.parseErrors += 1
            }
        }

        return summary
    }

    // MARK: - Packet dispatch

    private static func parsePacket(_ packet: Data, linkType: LinkType, into summary: inout PCAPSummary) throws {
        switch linkType {
        case .ieee80211:
            try parse80211Frame(packet, radiotapOffset: 0, into: &summary)
        case .ieee80211Radio:
            guard packet.count >= 4 else { return }
            let radiotapLen = Int(packet.readUInt16LE(at: 2))
            guard radiotapLen <= packet.count else { return }
            try parse80211Frame(packet, radiotapOffset: radiotapLen, into: &summary)
        case .unknown:
            return
        }
    }

    // MARK: - 802.11 Frame parsing

    private static func parse80211Frame(_ data: Data, radiotapOffset: Int, into summary: inout PCAPSummary) throws {
        let frameStart = data.startIndex + radiotapOffset
        guard data.endIndex - frameStart >= 2 else { return }

        // Read optional radiotap signal field for RSSI
        var rssi: Int? = nil
        if radiotapOffset >= 8 {
            rssi = extractRadiotapRSSI(data, headerLen: radiotapOffset)
        }

        let fc0 = data[frameStart]      // frame control byte 0
        let fc1 = data[frameStart + 1]  // frame control byte 1

        let frameTypeBits = (fc0 >> 2) & 0x03
        let subtype       = (fc0 >> 4) & 0x0F
        let retryBit      = (fc1 >> 3) & 0x01

        guard let frameType = FrameType(rawValue: frameTypeBits) else { return }

        switch frameType {
        case .management:
            try parseManagementFrame(data, frameStart: frameStart, subtype: subtype,
                                     rssi: rssi, retry: retryBit == 1, into: &summary)
        case .data:
            try parseDataFrame(data, frameStart: frameStart, rssi: rssi,
                               retry: retryBit == 1, into: &summary)
        case .control:
            // Count control frames against the BSSID in address 1 if available
            if data.endIndex - frameStart >= 10 {
                let bssid = macString(data, at: frameStart + 4)
                summary.records[bssid, default: BSSIDRecord(bssid: bssid, ssid: "")].counts.control += 1
            }
        }
    }

    // MARK: - Management frame

    private static func parseManagementFrame(_ data: Data, frameStart: Int, subtype: UInt8,
                                              rssi: Int?, retry: Bool, into summary: inout PCAPSummary) throws {
        // MAC header: FC(2) + Duration(2) + DA(6) + SA(6) + BSSID(6) + SeqCtrl(2) = 24 bytes
        guard data.endIndex - frameStart >= 24 else { return }

        let bssid = macString(data, at: frameStart + 16)

        var record = summary.records[bssid] ?? BSSIDRecord(bssid: bssid, ssid: "")

        switch ManagementSubtype(rawValue: subtype) {
        case .beacon:
            record.counts.beacons += 1
            if let rssi { record.signalSamples.append(rssi) }
            // Extract SSID from beacon fixed fields + IEs
            let bodyStart = frameStart + 24
            // Skip: timestamp(8) + interval(2) + capability(2) = 12 bytes fixed params
            let ieStart = bodyStart + 12
            if let ssid = extractSSID(from: data, ieStart: ieStart) {
                record.ssid = ssid
            }

        case .probeResponse:
            record.counts.probeResponses += 1
            let bodyStart = frameStart + 24
            let ieStart = bodyStart + 12
            if record.ssid.isEmpty, let ssid = extractSSID(from: data, ieStart: ieStart) {
                record.ssid = ssid
            }

        default:
            record.counts.otherManagement += 1
        }

        if retry { record.counts.retries += 1 }
        summary.records[bssid] = record
    }

    // MARK: - Data frame

    private static func parseDataFrame(_ data: Data, frameStart: Int,
                                        rssi: Int?, retry: Bool, into summary: inout PCAPSummary) throws {
        // Minimum MAC header is 24 bytes for data frames
        guard data.endIndex - frameStart >= 24 else { return }

        // Address 3 is the BSSID for data frames in infrastructure mode
        let bssid = macString(data, at: frameStart + 16)

        var record = summary.records[bssid] ?? BSSIDRecord(bssid: bssid, ssid: "")
        record.counts.dataFrames += 1
        if retry { record.counts.retries += 1 }
        if let rssi { record.signalSamples.append(rssi) }
        summary.records[bssid] = record
    }

    // MARK: - IE parsing

    private static func extractSSID(from data: Data, ieStart: Int) -> String? {
        var pos = ieStart
        while pos + 2 <= data.endIndex {
            let tag    = data[pos]
            let length = Int(data[pos + 1])
            pos += 2
            guard pos + length <= data.endIndex else { break }
            if tag == 0 {   // SSID element
                if length == 0 { return "" }
                let ssidData = data[pos ..< pos + length]
                return String(bytes: ssidData, encoding: .utf8)
                    ?? String(bytes: ssidData, encoding: .isoLatin1)
                    ?? "(non-UTF8)"
            }
            pos += length
        }
        return nil
    }

    // MARK: - Radiotap RSSI

    private static func extractRadiotapRSSI(_ data: Data, headerLen: Int) -> Int? {
        // Radiotap present flags are at offset 4 (4 bytes)
        guard headerLen >= 8 else { return nil }
        let present = data.readUInt32LE(at: data.startIndex + 4)
        // Bit 5 = DBM_ANTSIGNAL
        guard (present >> 5) & 1 == 1 else { return nil }

        // Walk the fields in order to find the signal byte.
        // We only handle the common single-extension case.
        var fieldOffset = 8
        // Skip FLAGS (bit 1) if present: 1 byte, align 1
        if (present >> 1) & 1 == 1 { fieldOffset += 1 }
        // Skip RATE (bit 2) if present: 1 byte, align 1
        if (present >> 2) & 1 == 1 { fieldOffset += 1 }
        // Skip CHANNEL (bit 3) if present: 4 bytes, align 2
        if (present >> 3) & 1 == 1 {
            fieldOffset = align(fieldOffset, to: 2)
            fieldOffset += 4
        }
        // Skip FHSS (bit 4) if present: 2 bytes, align 2
        if (present >> 4) & 1 == 1 {
            fieldOffset = align(fieldOffset, to: 2)
            fieldOffset += 2
        }
        // DBM_ANTSIGNAL (bit 5): 1 byte, align 1
        guard fieldOffset < headerLen, fieldOffset < data.count else { return nil }
        let raw = data[data.startIndex + fieldOffset]
        return Int(Int8(bitPattern: raw))
    }

    private static func align(_ offset: Int, to alignment: Int) -> Int {
        (offset + alignment - 1) & ~(alignment - 1)
    }

    // MARK: - MAC address

    private static func macString(_ data: Data, at offset: Int) -> String {
        guard offset + 6 <= data.endIndex else { return "00:00:00:00:00:00" }
        return (0..<6).map { String(format: "%02x", data[offset + $0]) }.joined(separator: ":")
    }
}

// MARK: - Data extensions

extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[index(startIndex, offsetBy: offset)]) |
               UInt16(self[index(startIndex, offsetBy: offset + 1)]) << 8
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let base = index(startIndex, offsetBy: offset)
        return UInt32(self[base]) |
               UInt32(self[base + 1]) << 8 |
               UInt32(self[base + 2]) << 16 |
               UInt32(self[base + 3]) << 24
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let base = index(startIndex, offsetBy: offset)
        return UInt32(self[base]) << 24 |
               UInt32(self[base + 1]) << 16 |
               UInt32(self[base + 2]) << 8 |
               UInt32(self[base + 3])
    }
}
