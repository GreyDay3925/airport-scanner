import SwiftUI

@main
struct AirportScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scanner") {
                Button("Scan Now") {}
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("PCAP") {
                Button("Open PCAP File…") {}
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
