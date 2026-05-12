// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirportScanner",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AirportScanner",
            path: "AirportScanner",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
