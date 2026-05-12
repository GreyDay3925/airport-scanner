# Airport Scanner

A macOS SwiftUI app with two tools for WiFi troubleshooting:

1. **WiFi Scanner** — GUI for the built-in `airport` tool; scans visible networks and shows channel/signal details.
2. **Capture Analyzer** — Opens `.pcap` files and summarises beacon counts, data frames, retry rates, and congestion indicators per network.

---

## Quick start — build & install on your Mac

### Option A: One-command DMG build

```bash
# Clone or download the project, then:
cd artifacts/AirportScanner
./build-dmg.sh
# → build/AirportScanner.dmg
```

Open the DMG, drag **AirportScanner** to Applications, and launch.  
**First launch:** right-click → Open to bypass Gatekeeper (ad-hoc signed, not notarized).

### Option B: Open in Xcode

1. Double-click **AirportScanner.xcodeproj** to open in Xcode
2. Select your Mac as the run destination
3. Press **⌘R** to build and run directly

### Requirements

- macOS 13 Ventura or later
- Xcode 15+ (for building)

---

## Share a DMG via GitHub Releases (recommended)

The included GitHub Actions workflow automatically builds a DMG and publishes a downloadable release whenever you push a version tag.

### Setup (one time)

1. Push this repo to GitHub
2. Go to **Settings → Actions → General** → set Workflow permissions to **Read and write**

### Publish a release

```bash
git tag v1.0
git push origin v1.0
```

GitHub Actions builds on a macOS runner, creates the DMG, and attaches it to a public **Releases** page. Anyone can download it from:

```
https://github.com/<your-username>/<repo>/releases/latest
```

You can also trigger a build manually at any time from **Actions → Build & Release DMG → Run workflow**.

---

## Project structure

```
AirportScanner/
├── AirportScanner.xcodeproj/   ← Open this in Xcode
│   └── project.pbxproj
├── AirportScanner/             ← All source files
│   ├── AirportScannerApp.swift
│   ├── ContentView.swift       ← Tab container + WiFi Scanner tab
│   ├── NetworkScanner.swift    ← Runs airport -s / -I
│   ├── NetworkEntry.swift      ← WiFi scan data models
│   ├── PCAPModels.swift        ← Frame counts, congestion models
│   ├── PCAPParser.swift        ← Pure Swift binary .pcap parser
│   ├── PCAPView.swift          ← Capture Analyzer tab UI
│   ├── Assets.xcassets/
│   ├── Info.plist
│   └── AirportScanner.entitlements
├── build-dmg.sh                ← One-command build + DMG packaging
└── .github/workflows/
    └── build.yml               ← GitHub Actions: auto-build on git tag
```

---

## Capturing a .pcap file

**Terminal (quickest):**
```bash
sudo tcpdump -i en0 -w ~/Desktop/capture.pcap
# Press Ctrl+C after 30–60 seconds
```

**Wireless Diagnostics (no Terminal):**
1. Hold **⌥ Option** and click the WiFi icon in the menu bar
2. Choose **Open Wireless Diagnostics**
3. **Window → Sniffer → Start**, wait, then Stop
4. Capture saves to `/var/tmp/`

---

## Congestion badges

| Badge | Retry rate | What it means |
|-------|-----------|---------------|
| ✓ Good | < 5 % | Channel is clean |
| ⚠ Some congestion | 5–15 % | Consider switching channel |
| ✗ Congested | > 15 % | Switch channel or investigate interference |

---

## Notes

- The `airport` binary path may change in future macOS versions. Verify path in `NetworkScanner.swift` if the scanner shows an error.
- The DMG produced by `build-dmg.sh` is **ad-hoc signed** but not notarized. Recipients must right-click → Open on first launch. For fully notarized distribution, an Apple Developer Program membership is required.
