// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Screenly",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Screenly",
            path: "Sources/Screenly",
            swiftSettings: [
                // Screenly talks to system-level APIs (Carbon hotkeys, the
                // `screencapture` process, AppKit panels) that are inherently
                // main-thread / single-owner. Swift 5 language mode keeps that
                // code readable without fighting strict-concurrency diagnostics.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
