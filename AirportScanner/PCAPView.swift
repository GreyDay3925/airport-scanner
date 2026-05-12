import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main PCAP tab

struct PCAPView: View {
    @State private var summaries: [PCAPSummary] = []
    @State private var selected: PCAPSummary?
    @State private var isImporting = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var focusSSID: String = ""
    @State private var showCaptureGuide = false

    var body: some View {
        NavigationSplitView {
            fileListSidebar
        } detail: {
            if let summary = selected {
                PCAPDetailView(summary: summary, focusSSID: $focusSSID)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 980, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isProcessing {
                    ProgressView().scaleEffect(0.75)
                        .help("Opening file…")
                }
                Button(action: { isImporting = true }) {
                    Label("Open Capture File", systemImage: "folder.badge.plus")
                }
                .disabled(isProcessing)
                .keyboardShortcut("o", modifiers: .command)
                .help("Open a .pcap capture file (⌘O)")

                Button { showCaptureGuide.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("How do I create a capture file?")
                .popover(isPresented: $showCaptureGuide, arrowEdge: .bottom) {
                    CaptureGuidePopover()
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType.pcap, UTType.pcapng,
                                  UTType(filenameExtension: "pcap")!],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .alert("Could not open file", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    var fileListSidebar: some View {
        VStack(spacing: 0) {
            if summaries.isEmpty {
                sidebarEmptyState
            } else {
                List(selection: $selected) {
                    ForEach(summaries, id: \.fileURL) { summary in
                        PCAPFileRow(summary: summary)
                            .tag(summary)
                    }
                    .onDelete { offsets in
                        summaries.remove(atOffsets: offsets)
                        if let sel = selected,
                           !summaries.contains(where: { $0.fileURL == sel.fileURL }) {
                            selected = summaries.last
                        }
                    }
                }
            }

            Divider()
            Button {
                isImporting = true
            } label: {
                Label("Open Capture File…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .navigationTitle("Capture Files")
    }

    var sidebarEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No files yet")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Open a .pcap file to start\nanalyzing your network.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail empty state

    var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 56))
                .foregroundStyle(.blue.opacity(0.6))

            VStack(spacing: 6) {
                Text("Analyze a Network Capture")
                    .font(.title2.weight(.semibold))
                Text("Open a .pcap file to see a breakdown of your WiFi traffic —\nhow many beacons were sent, how much data moved, and\nwhether your channel is congested.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HowToCaptureSummary(onOpenGuide: { showCaptureGuide = true })

            Button("Open Capture File…") { isImporting = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File import

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            errorMessage = err.localizedDescription
        case .success(let urls):
            isProcessing = true
            Task.detached(priority: .userInitiated) {
                var loaded: [PCAPSummary] = []
                var errors: [String] = []
                for url in urls {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let summary = try PCAPParser.parse(url: url)
                        loaded.append(summary)
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                await MainActor.run {
                    summaries.append(contentsOf: loaded)
                    if let last = loaded.last { selected = last }
                    if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - File row

struct PCAPFileRow: View {
    let summary: PCAPSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.fileURL.lastPathComponent)
                .font(.body.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Label("\(summary.totalPackets) packets", systemImage: "square.stack.3d.up")
                Text("·")
                Label("\(summary.uniqueSSIDs.count) networks", systemImage: "wifi")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Detail view

struct PCAPDetailView: View {
    let summary: PCAPSummary
    @Binding var focusSSID: String
    @State private var selectedBSSID: String?

    var displayedRecords: [BSSIDRecord] {
        if focusSSID.isEmpty { return summary.sortedRecords }
        return summary.sortedRecords.filter {
            $0.ssid.localizedCaseInsensitiveContains(focusSSID) ||
            $0.bssid.localizedCaseInsensitiveContains(focusSSID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            HStack(spacing: 0) {
                networkTable
                if let bssid = selectedBSSID, let record = summary.records[bssid] {
                    Divider()
                    NetworkInsightPanel(record: record)
                        .frame(width: 280)
                }
            }
        }
    }

    // MARK: - Summary header

    var summaryHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SummaryTile(
                    icon: "square.stack.3d.up", color: .blue,
                    label: "Total Packets",
                    value: "\(summary.totalPackets)",
                    tip: "Every piece of network data captured in this file."
                )
                Divider().frame(height: 48)
                SummaryTile(
                    icon: "antenna.radiowaves.left.and.right", color: .purple,
                    label: "Beacon Signals",
                    value: "\(summary.totalBeacons)",
                    tip: "Routers broadcast beacons to advertise their presence. High counts from many routers on the same channel can cause congestion."
                )
                Divider().frame(height: 48)
                SummaryTile(
                    icon: "arrow.up.arrow.down", color: .teal,
                    label: "Data Transfers",
                    value: "\(summary.totalDataFrames)",
                    tip: "Packets that carried actual content — web pages, videos, messages, etc."
                )
                Divider().frame(height: 48)
                SummaryTile(
                    icon: "arrow.counterclockwise", color: summary.totalRetries > 0 ? .orange : .secondary,
                    label: "Retried Packets",
                    value: "\(summary.totalRetries)",
                    tip: "Packets that had to be sent more than once. Many retries suggest interference or congestion."
                )
                Divider().frame(height: 48)
                SummaryTile(
                    icon: "clock", color: .secondary,
                    label: "Duration",
                    value: summary.duration.map { formatDuration($0) } ?? "—",
                    tip: "How long this capture covers."
                )
                Spacer()
            }

            Divider()

            // Filter bar
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter by network name…", text: $focusSSID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .help("Type your own network name to focus on it")
                if !focusSSID.isEmpty {
                    Button { focusSSID = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if !summary.uniqueSSIDs.isEmpty {
                    Menu("Jump to network") {
                        ForEach(summary.uniqueSSIDs.filter { !$0.isEmpty }, id: \.self) { ssid in
                            Button(ssid) { focusSSID = ssid }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Text("\(displayedRecords.count) network\(displayedRecords.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.background)
    }

    // MARK: - Network table

    var networkTable: some View {
        Table(displayedRecords, selection: $selectedBSSID) {

            TableColumn("Network Name") { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.ssid.isEmpty ? "(Hidden / data only)" : r.ssid)
                        .italic(r.ssid.isEmpty)
                        .lineLimit(1)
                    Text(r.bssid)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            TableColumn("Beacons") { r in
                HStack(spacing: 4) {
                    Text("\(r.counts.beacons)")
                        .monospacedDigit()
                    if r.counts.beacons > 500 {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("High beacon count on this channel may be contributing to congestion.")
                    }
                }
            }
            .width(80)

            TableColumn("Data Packets") { r in
                Text("\(r.counts.dataFrames)")
                    .monospacedDigit()
            }
            .width(90)

            TableColumn("Retried Packets") { r in
                HStack(spacing: 5) {
                    Text("\(r.counts.retries)")
                        .monospacedDigit()
                    if r.counts.retries > 0 {
                        Text("(\(Int(r.retryRate * 100))%)")
                            .font(.caption)
                            .foregroundStyle(retryColor(r.retryRate))
                    }
                }
            }
            .width(110)

            TableColumn("Connection Quality") { r in
                QualityBadge(level: r.congestionIndicator)
            }
            .width(130)

            TableColumn("Avg Signal") { r in
                if let rssi = r.averageRSSI {
                    HStack(spacing: 5) {
                        SignalStrengthIcon(rssi: rssi, size: 12)
                        Text("\(rssi) dBm")
                            .font(.system(size: 11, design: .monospaced))
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(90)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "hand.point.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Click a row to see a full explanation for that network.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    func retryColor(_ rate: Double) -> Color {
        rate > 0.15 ? .red : rate > 0.05 ? .orange : .secondary
    }

    func formatDuration(_ t: TimeInterval) -> String {
        if t < 60 { return String(format: "%.0fs", t) }
        let m = Int(t) / 60, s = Int(t) % 60
        return "\(m)m \(s)s"
    }
}

// MARK: - Insight panel (right sidebar)

struct NetworkInsightPanel: View {
    let record: BSSIDRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.ssid.isEmpty ? "(Hidden Network)" : record.ssid)
                        .font(.title3.weight(.semibold))
                    Text(record.bssid)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                QualityBadge(level: record.congestionIndicator)

                Text(record.congestionIndicator.friendlyExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    InsightRow(
                        icon: "antenna.radiowaves.left.and.right",
                        label: "Beacons",
                        value: "\(record.counts.beacons)",
                        tip: "How many times this router broadcast its presence. Normal routers send about 10 per second."
                    )
                    InsightRow(
                        icon: "arrow.up.arrow.down",
                        label: "Data packets",
                        value: "\(record.counts.dataFrames)",
                        tip: "Actual content packets — web pages, videos, etc."
                    )
                    InsightRow(
                        icon: "arrow.counterclockwise",
                        label: "Retried packets",
                        value: record.counts.retries == 0
                            ? "None ✓"
                            : "\(record.counts.retries) (\(Int(record.retryRate * 100))%)",
                        tip: "Packets that had to be re-sent. Ideally below 5%."
                    )
                    if let rssi = record.averageRSSI {
                        InsightRow(
                            icon: "wifi",
                            label: "Average signal",
                            value: "\(rssi) dBm",
                            tip: "Average signal strength seen in this capture. –50 is excellent; below –80 is weak."
                        )
                    }
                }

                if record.congestionIndicator != .low {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Suggestions", systemImage: "lightbulb.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        ForEach(record.congestionIndicator.suggestions, id: \.self) { tip in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(tip)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary)
    }
}

// MARK: - How-to summary (shown on empty state)

struct HowToCaptureSummary: View {
    let onOpenGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to create a capture file")
                .font(.callout.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                StepRow(number: "1", text: "Open Terminal (press ⌘Space and type Terminal)")
                StepRow(number: "2", text: "Type: sudo tcpdump -i en0 -w ~/capture.pcap")
                StepRow(number: "3", text: "Enter your Mac password when asked")
                StepRow(number: "4", text: "Wait 30–60 seconds, then press Control+C to stop")
                StepRow(number: "5", text: "Click Open Capture File and choose ~/capture.pcap")
            }

            Button("More details…", action: onOpenGuide)
                .font(.caption)
                .buttonStyle(.link)
        }
        .padding(16)
        .background(.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 440)
    }
}

struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.blue)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Capture guide popover

struct CaptureGuidePopover: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How to capture WiFi traffic")
                    .font(.headline)

                Text("A capture file (.pcap) is a recording of network packets. You need one to use this analyzer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Option 1 — Terminal (quickest)")
                    .font(.subheadline.weight(.semibold))

                CodeBlock("""
sudo tcpdump -i en0 -w ~/Desktop/capture.pcap
""")
                Text("Run this in Terminal. Press **Control+C** after 30–60 seconds to stop. The file saves to your Desktop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Option 2 — Wireless Diagnostics")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 4) {
                    StepRow(number: "1", text: "Hold Option (⌥) and click the WiFi icon in the menu bar")
                    StepRow(number: "2", text: "Choose Open Wireless Diagnostics")
                    StepRow(number: "3", text: "In the menu bar of that app: Window → Sniffer")
                    StepRow(number: "4", text: "Click Start and wait, then Stop")
                    StepRow(number: "5", text: "The capture file saves to /var/tmp/")
                }

                Divider()

                Label("Note: the capture only records network headers and control frames — not the content of your messages or browsing.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(width: 360, height: 480)
    }
}

struct CodeBlock: View {
    let code: String
    init(_ code: String) { self.code = code }

    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Shared components

struct SummaryTile: View {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let tip: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .help(tip)
    }
}

struct InsightRow: View {
    let icon: String
    let label: String
    let value: String
    let tip: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .help(tip)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit().weight(.medium))
        }
    }
}

struct QualityBadge: View {
    let level: CongestionLevel

    private var label: String {
        switch level {
        case .low:      return "Good"
        case .moderate: return "Some congestion"
        case .high:     return "Congested"
        }
    }

    private var icon: String {
        switch level {
        case .low:      return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .high:     return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch level {
        case .low:      return .green
        case .moderate: return .orange
        case .high:     return .red
        }
    }

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - UTType extension

extension UTType {
    static let pcap   = UTType(filenameExtension: "pcap")   ?? .data
    static let pcapng = UTType(filenameExtension: "pcapng") ?? .data
}

// MARK: - Model extensions

extension CongestionLevel {
    var friendlyExplanation: String {
        switch self {
        case .low:
            return "This network looks healthy. Fewer than 5% of packets had to be retried, which means the channel is mostly clear."
        case .moderate:
            return "Between 5% and 15% of packets had to be retried. There is some interference or competition on this channel. Switching to a less busy channel may improve performance."
        case .high:
            return "More than 15% of packets had to be retried — a strong sign of channel congestion or interference. Try switching to a different WiFi channel, moving closer to your router, or reducing the number of devices on the same network."
        }
    }

    var suggestions: [String] {
        switch self {
        case .low: return []
        case .moderate:
            return [
                "Log in to your router and try a different 2.4 GHz channel (1, 6, or 11) or a 5 GHz channel.",
                "Check how many nearby networks share your channel — the table above shows their beacon counts.",
                "Move your router to a more central location away from walls and appliances."
            ]
        case .high:
            return [
                "Change your WiFi channel immediately — this one is very congested.",
                "If possible, switch from 2.4 GHz to 5 GHz for much less interference.",
                "Look for nearby networks with high beacon counts sharing your channel.",
                "Check for interference sources: microwaves, baby monitors, and Bluetooth all use 2.4 GHz.",
                "Consider a mesh WiFi system if the building is large."
            ]
        }
    }
}
