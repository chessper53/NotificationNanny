import Foundation

/// Auto-dismiss timers, one per banner.
///
/// Since macOS 26 every banner lives in one long-lived host window, so a timer
/// keyed by window outlives the banner it was started for and fires on whichever
/// banner happens to be up by then. Keying by the banner's own identifier gives
/// each banner its full delay, and a banner that leaves early takes its timer
/// with it.
@MainActor
final class BannerDismissTimers {
    /// Runs `fire` after `delay` seconds; returns a closure that cancels it.
    typealias Schedule = (_ delay: Double, _ fire: @escaping @MainActor () -> Void) -> () -> Void

    private var cancels: [String: () -> Void] = [:]
    private let schedule: Schedule

    init(schedule: @escaping Schedule = BannerDismissTimers.dispatchAfter) {
        self.schedule = schedule
    }

    var armedIDs: Set<String> { Set(cancels.keys) }

    /// Starts a timer for each banner that doesn't have one yet. Banners that
    /// already have one keep it, so calling this on every sweep is safe.
    func arm(_ ids: [String], delay: Double, onFire: @escaping @MainActor (String) -> Void) {
        guard delay > 0 else { return }
        for id in ids where cancels[id] == nil {
            cancels[id] = schedule(delay) { [weak self] in
                guard let self, self.cancels.removeValue(forKey: id) != nil else { return }
                onFire(id)
            }
        }
    }

    /// Cancels the timers of banners that are no longer up.
    func prune(keeping present: Set<String>) {
        for id in cancels.keys where !present.contains(id) {
            cancels.removeValue(forKey: id)?()
        }
    }

    func cancelAll() {
        cancels.values.forEach { $0() }
        cancels.removeAll()
    }

    nonisolated static func dispatchAfter(_ delay: Double, _ fire: @escaping @MainActor () -> Void) -> () -> Void {
        let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}
