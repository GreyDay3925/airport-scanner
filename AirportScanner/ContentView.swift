import SwiftUI

// MARK: - Root container

struct ContentView: View {
    @State private var selectedTab: AppTab = .scanner

    enum AppTab: String, CaseIterable, Identifiable {
        case scanner = "WiFi Scanner"
        case pcap    = "Capture Analyzer"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .scanner: return "wifi"
            case .pcap:    return "doc.text.magnifyingglass"
            }
        }
        var description: String {
            switch self {
            case .scanner: return "See all nearby WiFi networks"
            case .pcap:    return "Analyse a saved network capture"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ScannerView()
                .tabItem { Label("WiFi Scanner", systemImage: "wifi") }
                .tag(AppTab.scanner)

            PCAPView()
                .tabItem { Label("Capture Analyzer", systemImage: "doc.text.magnifyingglass") }
                .tag(AppTab.pcap)
        }
        .frame(minWidth: 980, minHeight: 600)
    }
}

// MARK: - WiFi Scanner tab

struct ScannerView: View {
    @StateObject private var scanner = NetworkScanner()
    @State private var selectedNetwork: NetworkEntry?
    @State private var sortOrder = [KeyPathComparator(\NetworkEntry.rssi, order: .reverse)]
    @State private var searchText = ""
    @State private var showHelp = false

    var filteredNetworks: [NetworkEntry] {
        if searchText.isEmpty { return scanner.networks }
        return scanner.networks.filter {
            $0.ssid.localizedCaseInsensitiveContains(searchText) ||
            $0.channel.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarContent
        } detail: {
            if let network = selectedNetwork {
                NetworkDetailView(network: network,
                                  isMyNetwork: network.ssid == scanner.currentNetwork.ssid)
            } else {
                emptyDetail
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if scanner.isScanning {
                    ProgressView()
                        .scaleEffect(0.75)
                        .help("Scanning nearby networks…")
                }
                Button(action: { scanner.scan() }) {
                    Label(scanner.isScanning ? "Scanning…" : "Scan Now",
                          systemImage: "arrow.clockwise")
                }
                .disabled(scanner.isScanning)
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh the list of nearby WiFi networks  (⌘R)")

                Button { showHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("How to read this screen")
                .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                    ScannerHelpPopover()
                }
            }
        }
        .onAppear { scanner.scan() }
    }

    var sidebarContent: some View {
        VStack(spacing: 0) {
            connectedNetworkBanner
            Divider()

            if let error = scanner.errorMessage {
                errorView(error)
            } else if scanner.networks.isEmpty && !scanner.isScanning {
                emptyNetworkList
            } else {
                networkTable
            }
        }
        .navigationTitle("Nearby Networks")
        .searchable(text: $searchText, prompt: "Search by network name or channel…")
    }

    // MARK: - Connected banner

    var connectedNetworkBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("You are connected to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(scanner.currentNetwork.ssid == "—"
                     ? "Not connected"
                     : scanner.currentNetwork.ssid)
                    .font(.headline)
            }

            Spacer()

            if scanner.currentNetwork.rssi != 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    SignalStrengthIcon(rssi: scanner.currentNetwork.rssi, size: 20)
                    Text("Channel \(scanner.currentNetwork.channel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background)
        .help("This is the WiFi network your Mac is currently using.")
    }

    // MARK: - Table

    var networkTable: some View {
        Table(filteredNetworks, selection: $selectedNetwork, sortOrder: $sortOrder) {

            TableColumn("Signal", value: \.rssi) { entry in
                HStack(spacing: 6) {
                    SignalStrengthIcon(rssi: entry.rssi, size: 14)
                    Text(entry.signalLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 88, max: 100)

            TableColumn("Network Name", value: \.ssid) { entry in
                HStack(spacing: 6) {
                    if entry.ssid == scanner.currentNetwork.ssid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .help("This is your current network")
                    }
                    Text(entry.ssid.isEmpty ? "(Hidden network)" : entry.ssid)
                        .italic(entry.ssid.isEmpty)
                }
            }

            TableColumn("Channel", value: \.channel) { entry in
                Text(entry.channel)
                    .font(.system(size: 12, design: .monospaced))
            }
            .width(min: 64, max: 80)

            TableColumn("Security", value: \.security) { entry in
                SecurityBadge(security: entry.security)
            }
            .width(min: 120, max: 160)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .safeAreaInset(edge: .bottom) { tableFooter }
    }

    var tableFooter: some View {
        HStack {
            if let date = scanner.lastScanTime {
                Label("Scanned at \(date.formatted(date: .omitted, time: .standard))",
                      systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(scanner.networks.count) network\(scanner.networks.count == 1 ? "" : "s") found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.point.left")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a network")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Tap any row on the left to see full\ndetails about that network.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyNetworkList: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No networks found yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Click Scan Now to search for nearby WiFi networks.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Scan Now") { scanner.scan() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Could not scan networks")
                .font(.title3.weight(.medium))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Try Again") { scanner.scan() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Network Detail

struct NetworkDetailView: View {
    let network: NetworkEntry
    let isMyNetwork: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()
                infoSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var header: some View {
        HStack(alignment: .top, spacing: 14) {
            SignalStrengthIcon(rssi: network.rssi, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(network.ssid.isEmpty ? "(Hidden Network)" : network.ssid)
                        .font(.title2.weight(.semibold))
                        .italic(network.ssid.isEmpty)
                    if isMyNetwork {
                        Label("Your network", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text(network.bssid)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .help("Hardware address (MAC address) of this access point. Useful for support calls.")
            }
            Spacer()
        }
    }

    var infoSection: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading, spacing: 14
        ) {
            InfoCard(
                icon: "antenna.radiowaves.left.and.right",
                label: "Signal Strength",
                value: "\(network.rssi) dBm  (\(network.signalStrength.description))",
                note: "Closer to 0 is stronger. –50 is great; –80 is weak.",
                color: signalColor(network.rssi)
            )
            InfoCard(
                icon: "lock.shield",
                label: "Security",
                value: network.friendlySecurityLabel,
                note: network.securityExplanation,
                color: network.securityColor
            )
            InfoCard(
                icon: "dot.radiowaves.left.and.right",
                label: "Channel",
                value: network.channel,
                note: "Channels 1, 6, and 11 overlap less on 2.4 GHz. Channels above 36 are 5 GHz.",
                color: .blue
            )
            InfoCard(
                icon: "wifi.router",
                label: "Hardware Address",
                value: network.bssid,
                note: "Unique identifier of this access point. Also called BSSID or MAC address.",
                color: .secondary
            )
            InfoCard(
                icon: "speedometer",
                label: "HT Mode",
                value: network.ht,
                note: "Indicates whether the network supports higher throughput (HT = yes).",
                color: .purple
            )
            InfoCard(
                icon: "globe",
                label: "Country Code",
                value: network.cc.isEmpty ? "—" : network.cc,
                note: "Regulatory region this access point is configured for.",
                color: .teal
            )
        }
    }

    func signalColor(_ rssi: Int) -> Color {
        switch rssi {
        case ..<(-80): return .red
        case -80 ..< -60: return .orange
        case -60 ..< -40: return .yellow
        default: return .green
        }
    }
}

// MARK: - Help popover

struct ScannerHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How to read this screen")
                .font(.headline)

            HelpRow(icon: "wifi", color: .green,
                    title: "Signal Strength",
                    body: "How strong the WiFi signal is. More bars = stronger signal. Weak signal can cause slow speeds.")
            HelpRow(icon: "lock.shield", color: .blue,
                    title: "Security",
                    body: "Whether the network requires a password. WPA2/WPA3 = secure. Open = anyone can join.")
            HelpRow(icon: "dot.radiowaves.left.and.right", color: .orange,
                    title: "Channel",
                    body: "The radio frequency slice this network uses. Many networks on the same channel = congestion.")
            HelpRow(icon: "checkmark.circle.fill", color: .green,
                    title: "Your network",
                    body: "The green checkmark shows which network your Mac is currently connected to.")

            Divider()
            Text("Press ⌘R at any time to refresh the list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 320)
    }
}

struct HelpRow: View {
    let icon: String
    let color: Color
    let title: String
    let body: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Reusable components

struct SignalStrengthIcon: View {
    let rssi: Int
    let size: CGFloat

    private var bars: Int {
        switch rssi {
        case ..<(-80): return 1
        case -80 ..< -65: return 2
        case -65 ..< -50: return 3
        default: return 4
        }
    }

    private var color: Color {
        switch bars {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .green
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: size * 0.10) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1.5)
                    .frame(
                        width:  size * 0.18,
                        height: size * 0.18 + size * 0.18 * CGFloat(bar)
                    )
                    .foregroundStyle(bar <= bars ? color : Color.secondary.opacity(0.25))
            }
        }
        .frame(width: size * 0.9, height: size, alignment: .bottom)
    }
}

struct SecurityBadge: View {
    let security: String

    private var friendly: String {
        if security == "NONE" || security.isEmpty { return "Open" }
        if security.contains("WPA3") { return "WPA3 — Very secure" }
        if security.contains("WPA2") { return "WPA2 — Secure" }
        if security.contains("WPA") { return "WPA — Secure" }
        if security.contains("WEP") { return "WEP — Outdated" }
        return security
    }

    private var color: Color {
        if security == "NONE" || security.isEmpty { return .red }
        if security.contains("WPA3") { return .green }
        if security.contains("WPA") { return .blue }
        if security.contains("WEP") { return .orange }
        return .secondary
    }

    private var icon: String {
        if security == "NONE" || security.isEmpty { return "lock.open" }
        return "lock.fill"
    }

    var body: some View {
        Label(friendly, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
    }
}

struct InfoCard: View {
    let icon: String
    let label: String
    let value: String
    let note: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value.isEmpty ? "—" : value)
                .font(.body.weight(.medium))
                .textSelection(.enabled)
            Text(note)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - NetworkEntry helpers

extension NetworkEntry {
    var signalLabel: String {
        switch rssi {
        case ..<(-80): return "Weak"
        case -80 ..< -65: return "Fair"
        case -65 ..< -50: return "Good"
        default: return "Excellent"
        }
    }

    var friendlySecurityLabel: String {
        if security == "NONE" || security.isEmpty { return "Open — No password" }
        if security.contains("WPA3") { return "WPA3 — Very secure" }
        if security.contains("WPA2") { return "WPA2 — Secure" }
        if security.contains("WPA") { return "WPA — Secure" }
        if security.contains("WEP") { return "WEP — Outdated encryption" }
        return security
    }

    var securityExplanation: String {
        if security == "NONE" || security.isEmpty {
            return "Anyone nearby can see your traffic on this network. Avoid using it for sensitive tasks."
        }
        if security.contains("WPA3") { return "The latest and most secure WiFi protection standard." }
        if security.contains("WPA2") { return "Widely used and reliable protection for home and office networks." }
        if security.contains("WPA") { return "An older but generally acceptable security standard." }
        if security.contains("WEP") { return "Very old encryption that can be cracked easily. Avoid if possible." }
        return "Password protected."
    }

    var securityColor: Color {
        if security == "NONE" || security.isEmpty { return .red }
        if security.contains("WPA3") { return .green }
        if security.contains("WPA") { return .blue }
        if security.contains("WEP") { return .orange }
        return .secondary
    }
}
