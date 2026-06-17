import Foundation
import os

private let log = Logger(subsystem: "com.notificationnanny", category: "focus")

/// Detects whether a macOS Focus / Do Not Disturb mode is currently active.
///
/// macOS exposes no public API for Focus state, and the storage location has
/// moved between releases. This monitor reads the user's own Focus database
/// (the app is non-sandboxed, so this is permitted) and caches the result for a
/// short interval so banner repositioning — which can query 60×/sec — doesn't
/// hit disk every time.
///
/// Detection is intentionally isolated here: if Apple moves the store again,
/// only `readActiveState()` needs updating.
@MainActor
final class FocusModeMonitor {
    static let shared = FocusModeMonitor()

    private var cachedValue = false
    private var lastRead = Date.distantPast
    private let cacheTTL: TimeInterval = 1.0

    private init() {}

    /// True when any Focus / Do Not Disturb mode is active. Cached for `cacheTTL`.
    var isActive: Bool {
        if Date().timeIntervalSince(lastRead) < cacheTTL { return cachedValue }
        lastRead = Date()
        cachedValue = Self.readActiveState()
        return cachedValue
    }

    // MARK: - Detection

    /// Candidate Focus-assertion database locations, newest layout first. The
    /// first file that exists and parses determines the answer.
    private static var assertionFileCandidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/DoNotDisturb/DB/Assertions.json"),
        ]
    }

    private static func readActiveState() -> Bool {
        for url in assertionFileCandidates where FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // Layout: { "data": [ { "storeAssertionRecords": [ … ] } ] }
            // A non-empty storeAssertionRecords array means a Focus is asserted.
            if let dataArr = root["data"] as? [[String: Any]] {
                for entry in dataArr {
                    if let records = entry["storeAssertionRecords"] as? [Any], !records.isEmpty {
                        return true
                    }
                }
            }
            return false
        }
        // No known store found (e.g. macOS Tahoe relocated it). Fail open: treat
        // as "no Focus" so repositioning keeps working rather than silently pausing.
        return false
    }
}
