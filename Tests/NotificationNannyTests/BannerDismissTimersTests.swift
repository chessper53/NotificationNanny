import Foundation
import Testing
@testable import NotificationNannyCore

/// Shared hosts must not cause one banner to inherit another banner's timer.
@Suite("Banner dismiss timers") @MainActor
struct BannerDismissTimersTests {

    /// A scheduler the test fires by hand.
    @MainActor
    final class FakeClock {
        struct Pending { let delay: Double; let fire: @MainActor () -> Void; var cancelled = false }
        var pending: [Pending] = []

        lazy var schedule: BannerDismissTimers.Schedule = { [unowned self] delay, fire in
            self.pending.append(Pending(delay: delay, fire: fire))
            let index = self.pending.count - 1
            return { [unowned self] in self.pending[index].cancelled = true }
        }

        /// Fires every timer that hasn't been cancelled, in the order they were started.
        func fireAll() {
            let due = pending.filter { !$0.cancelled }
            pending.removeAll()
            due.forEach { $0.fire() }
        }

        var live: Int { pending.filter { !$0.cancelled }.count }
    }

    @Test func arm_startsOneTimerPerBanner() {
        let clock = FakeClock()
        let timers = BannerDismissTimers(schedule: clock.schedule)
        var fired: [String] = []

        timers.arm(["a", "b"], delay: 10) { fired.append($0) }
        #expect(clock.live == 2)
        #expect(clock.pending.allSatisfy { $0.delay == 10 })

        clock.fireAll()
        #expect(Set(fired) == ["a", "b"])
        #expect(timers.armedIDs.isEmpty)
    }

    @Test func arm_isIdempotentPerBanner() {
        let clock = FakeClock()
        let timers = BannerDismissTimers(schedule: clock.schedule)

        timers.arm(["a"], delay: 10) { _ in }
        timers.arm(["a"], delay: 10) { _ in }
        timers.arm(["a", "b"], delay: 10) { _ in }

        #expect(clock.live == 2)
        #expect(timers.armedIDs == ["a", "b"])
    }

    @Test func newBannerInSameHost_getsItsOwnTimer() {
        let clock = FakeClock()
        let timers = BannerDismissTimers(schedule: clock.schedule)
        var fired: [String] = []

        timers.arm(["first"], delay: 10) { fired.append($0) }
        timers.prune(keeping: [])                       // first banner left on its own
        timers.arm(["second"], delay: 10) { fired.append($0) }

        clock.fireAll()
        #expect(fired == ["second"])
    }

    @Test func prune_cancelsOnlyBannersThatLeft() {
        let clock = FakeClock()
        let timers = BannerDismissTimers(schedule: clock.schedule)
        var fired: [String] = []

        timers.arm(["a", "b", "c"], delay: 5) { fired.append($0) }
        timers.prune(keeping: ["b"])

        #expect(timers.armedIDs == ["b"])
        clock.fireAll()
        #expect(fired == ["b"])
    }

    @Test func zeroDelay_armsNothing() {
        let clock = FakeClock()
        let timers = BannerDismissTimers(schedule: clock.schedule)

        timers.arm(["a"], delay: 0) { _ in }
        #expect(clock.live == 0)
        #expect(timers.armedIDs.isEmpty)
    }

    @Test func cancelAll_stopsEverything() {
        let clock = FakeClock()
        let timers = BannerDismissTimers(schedule: clock.schedule)
        var fired: [String] = []

        timers.arm(["a", "b"], delay: 5) { fired.append($0) }
        timers.cancelAll()

        clock.fireAll()
        #expect(fired.isEmpty)
        #expect(timers.armedIDs.isEmpty)
    }

    /// A fired identifier is forgotten and can be armed again if it is still present.
    @Test func firedBanner_canBeArmedAgain() {
        let clock = FakeClock()
        let timers = BannerDismissTimers(schedule: clock.schedule)

        timers.arm(["a"], delay: 5) { _ in }
        clock.fireAll()
        timers.arm(["a"], delay: 5) { _ in }

        #expect(clock.live == 1)
    }
}
