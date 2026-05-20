// swift-tools-version: 5.9
import PackageDescription

// This Package.swift is provided so the sources type-check in Xcode / SwiftPM,
// but the recommended way to RUN NotificationNanny is via an Xcode App target
// (see README). A plain SPM executable can't easily ship the Info.plist /
// LSUIElement settings a menu-bar app needs.
let package = Package(
    name: "NotificationNanny",
    platforms: [.macOS(.v14)],
    targets: [
        // All app logic lives here so tests can @testable import it.
        .target(
            name: "NotificationNannyCore",
            path: "Sources/NotificationNannyCore"
        ),
        // Thin executable: just the @main entry point.
        .executableTarget(
            name: "NotificationNanny",
            dependencies: ["NotificationNannyCore"],
            path: "Sources/NotificationNanny"
        ),
        .testTarget(
            name: "NotificationNannyTests",
            dependencies: ["NotificationNannyCore"],
            path: "Tests/NotificationNannyTests"
        ),
    ]
)
