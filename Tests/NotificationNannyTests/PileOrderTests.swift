import Testing
@testable import NotificationNannyCore

@Suite("Pile order")
struct PileOrderTests {

    @Test func nothingLeaving_isTheCurrentOrder() {
        #expect(PileOrder.merge(current: ["c", "b", "a"], previous: ["b", "a"], leaving: []) == ["c", "b", "a"])
    }

    @Test func middleLeaves_keepsItsSlot() {
        #expect(PileOrder.merge(current: ["a", "c"], previous: ["a", "b", "c"], leaving: ["b"]) == ["a", "b", "c"])
    }

    @Test func topLeaves_staysOnTop() {
        #expect(PileOrder.merge(current: ["b", "c"], previous: ["a", "b", "c"], leaving: ["a"]) == ["a", "b", "c"])
    }

    @Test func bottomLeaves_staysAtTheBottom() {
        #expect(PileOrder.merge(current: ["a", "b"], previous: ["a", "b", "c"], leaving: ["c"]) == ["a", "b", "c"])
    }

    @Test func newArrivalAndLeaving_together() {
        #expect(PileOrder.merge(current: ["d", "a", "c"], previous: ["a", "b", "c"], leaving: ["b"]) == ["d", "a", "b", "c"])
    }

    @Test func neighboursLeaving_keepTheirOrder() {
        #expect(PileOrder.merge(current: ["a", "d"], previous: ["a", "b", "c", "d"], leaving: ["b", "c"]) == ["a", "b", "c", "d"])
    }

    @Test func everythingLeaving_keepsThePile() {
        #expect(PileOrder.merge(current: [], previous: ["a", "b"], leaving: ["a", "b"]) == ["a", "b"])
    }

    // MARK: Arrange

    /// macOS's order, newest first, with when each was first seen.
    private let seen: [String: Double] = ["a": 1, "b": 2, "c": 3]

    @Test func arrange_newestOnTop() {
        #expect(PileOrder.arrange(["c", "b", "a"], firstSeen: seen, newestAtBottom: false) == ["c", "b", "a"])
    }

    @Test func arrange_newestAtBottom() {
        #expect(PileOrder.arrange(["c", "b", "a"], firstSeen: seen, newestAtBottom: true) == ["a", "b", "c"])
    }

    /// Native ordering can put a newer Temporary banner below Persistent banners.
    @Test func arrange_followsArrivalNotMacOSOrder() {
        let seen = ["persistent1": 1.0, "persistent2": 2, "temporary": 3]
        let macOS = ["persistent2", "persistent1", "temporary"]
        #expect(PileOrder.arrange(macOS, firstSeen: seen, newestAtBottom: false) == ["temporary", "persistent2", "persistent1"])
        #expect(PileOrder.arrange(macOS, firstSeen: seen, newestAtBottom: true) == ["persistent1", "persistent2", "temporary"])
    }

    @Test func arrange_tiesKeepMacOSOrder() {
        let same = ["x": 5.0, "y": 5, "z": 5]
        #expect(PileOrder.arrange(["x", "y", "z"], firstSeen: same, newestAtBottom: false) == ["x", "y", "z"])
        #expect(PileOrder.arrange(["x", "y", "z"], firstSeen: same, newestAtBottom: true) == ["z", "y", "x"])
    }

    @Test func doneLeaving_isDropped() {
        #expect(PileOrder.merge(current: ["a"], previous: ["a", "b"], leaving: []) == ["a"])
    }

    // MARK: Split

    private static let spots = ["s1": "top", "s2": "top", "o1": "bottom", "o2": "bottom"]

    private func split(_ current: [String], previous: [String] = [], leaving: Set<String> = []) -> [[String]] {
        PileOrder.split(current: current, previous: previous, leaving: leaving) { Self.spots[$0] ?? "?" }
            .map(\.ids)
    }

    @Test func oneSpot_isOnePile() {
        #expect(split(["s2", "s1"]) == [["s2", "s1"]])
    }

    @Test func twoSpots_twoPiles_eachInOrder() {
        #expect(split(["o2", "s2", "o1", "s1"]) == [["o2", "o1"], ["s2", "s1"]])
    }

    @Test func leaving_staysInItsOwnPile() {
        #expect(split(["s1", "o2"], previous: ["s1", "o1", "o2"], leaving: ["o1"]) == [["s1"], ["o1", "o2"]])
    }

    @Test func pileOfOnlyLeaving_lastsItsExit() {
        #expect(split(["s1"], previous: ["s1", "o1"], leaving: ["o1"]) == [["s1"], ["o1"]])
        #expect(split(["s1"], previous: ["s1", "o1"]) == [["s1"]])
    }
}
