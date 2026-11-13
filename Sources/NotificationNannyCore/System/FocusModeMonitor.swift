import Foundation
import os

private let log = Logger(subsystem: "com.notificationnanny", category: "focus")

/// Poll the private Focus store off the main actor; placement reads only the cached state.
@MainActor
final class FocusModeMonitor: ObservableObject {
    static let shared = FocusModeMonitor()

    private(set) var isActive = false
    /// Nil until checked, then whether the Focus store was readable.
    /// Unreadable stores report no active Focus so Settings can explain why pausing is unavailable.
    @Published private(set) var storeReadable: Bool?
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
                    if self.storeReadable != readable { self.storeReadable = readable }
                }
                try? await Task.sleep(nanoseconds: ttlNanoseconds)
            }
        }
    }

    deinit { refreshTask?.cancel() }

    // MARK: Detection

    /// Try known Focus stores in order; NN_FOCUS_ASSERTIONS overrides them for isolated lab runs.
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
            // A nonempty storeAssertionRecords array means Focus is active.
            if let dataArr = root["data"] as? [[String: Any]] {
                for entry in dataArr {
                    if let records = entry["storeAssertionRecords"] as? [Any], !records.isEmpty {
                        return (true, true)
                    }
                }
            }
            return (false, true)
        }
        // An unknown or unreadable store leaves repositioning enabled.
        return (false, false)
    }
}
