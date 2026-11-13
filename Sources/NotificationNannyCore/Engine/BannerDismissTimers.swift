import Foundation

/// Key dismissal timers by banner identifier because the shared host outlives individual banners.
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

    /// Arms only new identifiers; existing banners keep their original deadlines.
    func arm(_ ids: [String], delay: Double, onFire: @escaping @MainActor (String) -> Void) {
        guard delay > 0 else { return }
        for id in ids where cancels[id] == nil {
            cancels[id] = schedule(delay) { [weak self] in
                guard let self, self.cancels.removeValue(forKey: id) != nil else { return }
                onFire(id)
            }
        }
    }

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
