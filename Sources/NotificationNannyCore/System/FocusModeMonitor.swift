import Foundation
import os

private let log = Logger(subsystem: "com.notificationnanny", category: "focus")

/// Detects whether a macOS Focus / Do Not Disturb mode is currently active.
///
/// macOS exposes no public API for Focus state, and the storage location has
/// moved between releases. This monitor reads the user's own Focus database
/// (the app is non-sandboxed, so this is permitted) on a detached background
/// task every `cacheTTL`, so `isActive` — read from the repositioner's hot AX
/// path, potentially 60×/sec — is a plain property read with no disk I/O ever
/// on the main actor.
///
/// Detection is intentionally isolated here: if Apple moves the store again,
/// only `readActiveState()` needs updating.
@MainActor
final class FocusModeMonitor {
    static let shared = FocusModeMonitor()

    private(set) var isActive = false
    /// Whether the Focus store could be read on the last check: nil before the first one.
    /// False most often means macOS denied access (it sits behind Full Disk Access on
    /// recent releases), and then `isActive` is always false whatever the real Focus is.
    private(set) var storeReadable: Bool?
    private let cacheTTL: TimeInterval = 1.0
    private var refreshTask: Task<Void, Never>?

    private init() {
        let ttlNanoseconds = UInt64(cacheTTL * 1_000_000_000)
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let (value, readable) = Self.readActiveState()
                guard let self else { return }
                await MainActor.run {
                    self.isActive = value
                    self.storeReadable = readable
                }
                try? await Task.sleep(nanoseconds: ttlNanoseconds)
            }
        }
    }

    deinit { refreshTask?.cancel() }

    // MARK: - Detection

    /// Candidate Focus-assertion database locations, newest layout first. The
    /// first file that exists and parses determines the answer. NN_FOCUS_ASSERTIONS=<path>
    /// replaces them with one file, so a scripted run can switch a Focus on and off.
    private nonisolated static var assertionFileCandidates: [URL] {
        if let path = ProcessInfo.processInfo.environment["NN_FOCUS_ASSERTIONS"] {
            return [URL(filePath: path)]
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/DoNotDisturb/DB/Assertions.json"),
        ]
    }

    /// Whether a Focus is asserted, and whether a store could be read at all.
    private nonisolated static func readActiveState() -> (active: Bool, readable: Bool) {
        // `fileExists` is false for a file behind TCC as well, so try the read regardless.
        for url in assertionFileCandidates {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // Layout: { "data": [ { "storeAssertionRecords": [ … ] } ] }
            // A non-empty storeAssertionRecords array means a Focus is asserted.
            if let dataArr = root["data"] as? [[String: Any]] {
                for entry in dataArr {
                    if let records = entry["storeAssertionRecords"] as? [Any], !records.isEmpty {
                        return (true, true)
                    }
                }
            }
            return (false, true)
        }
        // No known store found (e.g. macOS Tahoe relocated it). Fail open: treat
        // as "no Focus" so repositioning keeps working rather than silently pausing.
        return (false, false)
    }
}
