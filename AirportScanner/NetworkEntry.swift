import Foundation

struct NetworkEntry: Identifiable, Hashable {
    let id = UUID()
    let ssid: String
    let bssid: String
    let rssi: Int
    let channel: String
    let ht: String
    let cc: String
    let security: String

    var signalStrength: SignalStrength {
        switch rssi {
        case ..<(-80): return .weak
        case -80 ..< -60: return .fair
        case -60 ..< -40: return .good
        default: return .excellent
        }
    }

    var signalBars: String {
        switch signalStrength {
        case .weak:      return "▂___"
        case .fair:      return "▂▄__"
        case .good:      return "▂▄▆_"
        case .excellent: return "▂▄▆█"
        }
    }

    enum SignalStrength {
        case weak, fair, good, excellent
    }
}

struct CurrentNetworkInfo {
    let ssid: String
    let bssid: String
    let channel: String
    let rssi: Int
    let noise: Int
    let txRate: String
    let mcsIndex: String
    let security: String
    let state: String

    static var empty: CurrentNetworkInfo {
        CurrentNetworkInfo(ssid: "—", bssid: "—", channel: "—",
                           rssi: 0, noise: 0, txRate: "—",
                           mcsIndex: "—", security: "—", state: "Not connected")
    }
}
