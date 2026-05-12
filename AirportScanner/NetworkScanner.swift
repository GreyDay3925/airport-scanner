import Foundation
import Combine

@MainActor
final class NetworkScanner: ObservableObject {
    @Published var networks: [NetworkEntry] = []
    @Published var currentNetwork: CurrentNetworkInfo = .empty
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var lastScanTime: Date?

    private let airportPath = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil

        Task {
            async let scanResult = runAirport(args: ["-s"])
            async let infoResult = runAirport(args: ["-I"])

            let (scanOutput, infoOutput) = await (scanResult, infoResult)

            networks = parseScanOutput(scanOutput)
            currentNetwork = parseCurrentNetworkInfo(infoOutput)
            lastScanTime = Date()
            isScanning = false
        }
    }

    func refreshCurrentNetwork() {
        Task {
            let output = await runAirport(args: ["-I"])
            currentNetwork = parseCurrentNetworkInfo(output)
        }
    }

    private func runAirport(args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.airportPath)
                process.arguments = args

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to run airport: \(error.localizedDescription)\n\nEnsure the airport utility exists at:\n\(self.airportPath)"
                    }
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func parseScanOutput(_ output: String) -> [NetworkEntry] {
        var entries: [NetworkEntry] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() {
            let trimmed = line
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 5 else { continue }

            let bssid = parts.first(where: { $0.contains(":") && $0.count == 17 }) ?? "—"
            let bssidIndex = parts.firstIndex(where: { $0 == bssid }) ?? 1

            let ssid = parts[0..<max(1, bssidIndex)].joined(separator: " ")
            let rssi = Int(bssidIndex < parts.count - 1 ? parts[bssidIndex + 1] : "0") ?? 0
            let channel = bssidIndex + 2 < parts.count ? parts[bssidIndex + 2] : "—"
            let ht = bssidIndex + 3 < parts.count ? parts[bssidIndex + 3] : "—"
            let cc = bssidIndex + 4 < parts.count ? parts[bssidIndex + 4] : "—"
            let security = bssidIndex + 5 < parts.count
                ? parts[(bssidIndex + 5)...].joined(separator: " ")
                : "NONE"

            entries.append(NetworkEntry(
                ssid: ssid,
                bssid: bssid,
                rssi: rssi,
                channel: channel,
                ht: ht,
                cc: cc,
                security: security
            ))
        }

        return entries.sorted { $0.rssi > $1.rssi }
    }

    private func parseCurrentNetworkInfo(_ output: String) -> CurrentNetworkInfo {
        var dict: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2 {
                dict[parts[0]] = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }

        let state = dict["AirPort"] ?? dict["agrCtlRSSI"].map { _ in "Connected" } ?? "Not connected"

        guard let rssiStr = dict["agrCtlRSSI"], let rssi = Int(rssiStr) else {
            return CurrentNetworkInfo(
                ssid: dict["SSID"] ?? "—",
                bssid: dict["BSSID"] ?? "—",
                channel: dict["channel"] ?? "—",
                rssi: 0, noise: 0,
                txRate: dict["lastTxRate"] ?? "—",
                mcsIndex: dict["MCS"] ?? "—",
                security: dict["link auth"] ?? "—",
                state: state
            )
        }

        return CurrentNetworkInfo(
            ssid: dict["SSID"] ?? "—",
            bssid: dict["BSSID"] ?? "—",
            channel: dict["channel"] ?? "—",
            rssi: rssi,
            noise: Int(dict["agrCtlNoise"] ?? "0") ?? 0,
            txRate: dict["lastTxRate"].map { "\($0) Mbps" } ?? "—",
            mcsIndex: dict["MCS"] ?? "—",
            security: dict["link auth"] ?? "—",
            state: state
        )
    }
}
