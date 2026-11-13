// swift-tools-version: 5.9
import PackageDescription

// Build and assemble app bundles with the repository scripts.
let package = Package(
    name: "NotificationNanny",
    platforms: [.macOS(.v14)],
    targets: [
        // Separate app logic so tests can import it.
        .target(
            name: "NotificationNannyCore",
            path: "Sources/NotificationNannyCore"
        ),
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
