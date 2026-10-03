import Testing
@testable import NotificationNannyCore

/// A leaving overlay keeps its slot, between the same neighbours, until its
/// exit animation is over, so the overlay below doesn't slide under it.
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

    /// A new banner arrives on top while one in the middle leaves.
    @Test func newArrivalAndLeaving_together() {
        #expect(PileOrder.merge(current: ["d", "a", "c"], previous: ["a", "b", "c"], leaving: ["b"]) == ["d", "a", "b", "c"])
    }

    @Test func neighboursLeaving_keepTheirOrder() {
        #expect(PileOrder.merge(current: ["a", "d"], previous: ["a", "b", "c", "d"], leaving: ["b", "c"]) == ["a", "b", "c", "d"])
    }

    @Test func everythingLeaving_keepsThePile() {
        #expect(PileOrder.merge(current: [], previous: ["a", "b"], leaving: ["a", "b"]) == ["a", "b"])
    }

    /// Only ids still in their exit animation are kept.
    @Test func doneLeaving_isDropped() {
        #expect(PileOrder.merge(current: ["a"], previous: ["a", "b"], leaving: []) == ["a"])
    }
}
