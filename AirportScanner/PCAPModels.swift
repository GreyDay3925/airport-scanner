import Foundation

enum LinkType: UInt32 {
    case ieee80211      = 105
    case ieee80211Radio = 127
    case unknown        = 0xFFFF
}

struct FrameCounts {
    var beacons: Int = 0
    var dataFrames: Int = 0
    var retries: Int = 0
    var probeResponses: Int = 0
    var otherManagement: Int = 0
    var control: Int = 0

    var total: Int { beacons + dataFrames + retries + probeResponses + otherManagement + control }
}

struct BSSIDRecord {
    let bssid: String
    var ssid: String
    var counts: FrameCounts = FrameCounts()
    var lastSeenChannel: Int?
    var signalSamples: [Int] = []

    var averageRSSI: Int? {
        guard !signalSamples.isEmpty else { return nil }
        return signalSamples.reduce(0, +) / signalSamples.count
    }

    var retryRate: Double {
        guard counts.dataFrames + counts.retries > 0 else { return 0 }
        return Double(counts.retries) / Double(counts.dataFrames + counts.retries)
    }

    var congestionIndicator: CongestionLevel {
        if retryRate > 0.15 { return .high }
        if retryRate > 0.05 { return .moderate }
        return .low
    }
}

enum CongestionLevel: String {
    case low      = "Low"
    case moderate = "Moderate"
    case high     = "High"

    var colorName: String {
        switch self {
        case .low:      return "green"
        case .moderate: return "orange"
        case .high:     return "red"
        }
    }
}

struct PCAPSummary {
    let fileURL: URL
    var totalPackets: Int = 0
    var parsedPackets: Int = 0
    var parseErrors: Int = 0
    var linkType: LinkType = .unknown
    var firstTimestamp: Date?
    var lastTimestamp: Date?
    var records: [String: BSSIDRecord] = [:]     // keyed by BSSID

    var duration: TimeInterval? {
        guard let first = firstTimestamp, let last = lastTimestamp else { return nil }
        return last.timeIntervalSince(first)
    }

    var sortedRecords: [BSSIDRecord] {
        records.values.sorted { a, b in
            (b.counts.beacons + b.counts.dataFrames) < (a.counts.beacons + a.counts.dataFrames)
        }
    }

    var totalBeacons: Int   { records.values.reduce(0) { $0 + $1.counts.beacons } }
    var totalDataFrames: Int { records.values.reduce(0) { $0 + $1.counts.dataFrames } }
    var totalRetries: Int   { records.values.reduce(0) { $0 + $1.counts.retries } }
    var uniqueSSIDs: [String] { Array(Set(records.values.map { $0.ssid })).sorted() }
}
