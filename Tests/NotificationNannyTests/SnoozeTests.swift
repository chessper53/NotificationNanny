import Foundation
import Testing
@testable import NotificationNannyCore

/// Snooze ("pause for N minutes") and the `isActive` master gate that the
/// repositioner consults before touching any banner.
@Suite("Snooze") @MainActor
struct SnoozeTests {

    private func makeSettings(_ configure: (UserDefaults) -> Void = { _ in }) -> AppSettings {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        configure(ud)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        return AppSettings(defaults: ud, knownAppsFileURL: tempURL)
    }

    @Test func default_notSnoozed_andActive() {
        let s = makeSettings()
        #expect(s.isSnoozed == false)
        #expect(s.isActive == true)
    }

    @Test func snooze_pausesAndSetsFutureDate() {
        let s = makeSettings()
        s.snooze(minutes: 5)
        #expect(s.isSnoozed == true)
        #expect(s.isActive == false)
        #expect(s.snoozedUntil != nil)
        #expect((s.snoozedUntil ?? .distantPast) > Date())
    }

    @Test func endSnooze_resumesImmediately() {
        let s = makeSettings()
        s.snooze(minutes: 30)
        s.endSnooze()
        #expect(s.isSnoozed == false)
        #expect(s.isActive == true)
        #expect(s.snoozedUntil == nil)
    }

    @Test func disabled_isNeverActive() {
        let s = makeSettings()
        s.isEnabled = false
        #expect(s.isActive == false)
        s.snooze(minutes: 5)
        #expect(s.isActive == false)
    }

    @Test func init_ignoresExpiredSnooze() {
        // A snooze whose deadline already passed must not survive a relaunch.
        let past = Date().addingTimeInterval(-60)
        let s = makeSettings { $0.set(past, forKey: "snoozedUntil") }
        #expect(s.isSnoozed == false)
        #expect(s.snoozedUntil == nil)
    }

    @Test func init_honoursLiveSnooze() {
        let future = Date().addingTimeInterval(600)
        let s = makeSettings { $0.set(future, forKey: "snoozedUntil") }
        #expect(s.isSnoozed == true)
        #expect(s.isActive == false)
    }
}
