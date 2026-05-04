import AppKit
import CoreGraphics
import os

private let log = Logger(subsystem: "com.notificationnanny", category: "probe")

/// Diagnostics: enumerate all on-screen windows via CGWindowList and log
/// candidates that look like notification banners. Used to figure out which
/// process actually draws notifications on the running macOS version.
enum NotificationProbe {
    static func dumpOnScreenWindows(tag: String) {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID)
                as? [[String: Any]] else {
            log.warning("[\(tag, privacy: .public)] CGWindowListCopyWindowInfo returned nil")
            return
        }

        log.info("[\(tag, privacy: .public)] === \(info.count) on-screen windows ===")

        // Group by owning process so we can see at a glance who has windows.
        var byOwner: [String: Int] = [:]
        var candidates: [String] = []

        for w in info {
            let owner = w["kCGWindowOwnerName"] as? String ?? "?"
            let pid = (w["kCGWindowOwnerPID"] as? Int) ?? 0
            let layer = (w["kCGWindowLayer"] as? Int) ?? 0
            let bounds = w["kCGWindowBounds"] as? [String: CGFloat] ?? [:]
            let x = bounds["X"] ?? 0
            let y = bounds["Y"] ?? 0
            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0

            byOwner[owner, default: 0] += 1

            // Banner heuristic: smallish floating window above normal layer
            // (notification banners typically use layer 8/19/24 and are
            // 300–500 wide × 70–200 tall).
            if layer >= 1, width >= 200, width <= 600, height >= 50, height <= 250 {
                candidates.append(
                    "  candidate: \(owner) pid=\(pid) layer=\(layer) "
                    + "bounds=(\(Int(x)),\(Int(y)) \(Int(width))x\(Int(height)))"
                )
            }
        }

        let summary = byOwner.sorted { $0.value > $1.value }
            .prefix(8)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        log.info("[\(tag, privacy: .public)] owners: \(summary, privacy: .public)")

        for c in candidates {
            log.info("[\(tag, privacy: .public)] \(c, privacy: .public)")
        }
    }
}
