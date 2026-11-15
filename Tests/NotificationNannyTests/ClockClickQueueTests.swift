import Testing
@testable import NotificationNannyCore

@Suite("Clock input pairing")
struct ClockClickQueueTests {
    @Test func missingReleaseCannotBlockLaterClicks() {
        var queue = ClockClickQueue<Int, Int>()
        queue.press(1, on: 10, missingRelease: { -$0 })
        // A native panel/tap transition lost the first release.
        queue.press(2, on: 20, missingRelease: { -$0 })
        #expect(queue.first?.down == 1)
        #expect(queue.first?.up == -1)
        let released = queue.release(-2)
        #expect(released)
        queue.removeFirst()
        #expect(queue.first?.down == 2)
        #expect(queue.first?.up == -2)
        #expect(queue.first?.destination == 20)
    }

    @Test func clicksArrivingDuringCaptureRetainTheirPairsAndOrder() {
        var queue = ClockClickQueue<Int, Int>()
        for i in 1...20 {
            queue.press(i, on: i % 2, missingRelease: { -$0 })
            let released = queue.release(-i)
            #expect(released)
        }
        for i in 1...20 {
            #expect(queue.first?.down == i)
            #expect(queue.first?.up == -i)
            #expect(queue.first?.destination == i % 2)
            queue.removeFirst()
        }
        #expect(queue.count == 0)
        let strayRelease = queue.release(99)
        #expect(!strayRelease)
    }

    @Test func rapidTogglePairsPreserveTheFinalIntent() {
        var queue = ClockClickQueue<Int, Int>()
        for i in 1...21 {
            queue.press(i, on: 1, missingRelease: { -$0 })
            queue.release(-i)
        }
        let removed = queue.cancelPairedToggles(sameDestination: ==)
        #expect(removed == 20)
        #expect(queue.count == 1)
        #expect(queue.first?.down == 21)
        #expect(queue.first?.up == -21)
    }

    @Test func differentClocksAndUnreleasedPressesAreNotCancelled() {
        var queue = ClockClickQueue<Int, Int>()
        queue.press(1, on: 10, missingRelease: { -$0 })
        queue.release(-1)
        queue.press(2, on: 20, missingRelease: { -$0 })
        queue.release(-2)
        let removed = queue.cancelPairedToggles(sameDestination: ==)
        #expect(removed == 0)
        #expect(queue.count == 2)
        queue.removeAll()
        queue.press(1, on: 10, missingRelease: { -$0 })
        queue.release(-1)
        queue.press(2, on: 10, missingRelease: { -$0 })
        let unfinishedRemoved = queue.cancelPairedToggles(sameDestination: ==)
        #expect(unfinishedRemoved == 0)
        #expect(queue.count == 2)
    }
}
