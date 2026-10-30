import AppKit
import Testing
@testable import NotificationNannyCore

/// Where the custom Notification Center opens across the screen, from its side and the
/// offset dragged in Settings.
@Suite("NC panel offset") @MainActor
struct NCPanelOffsetTests {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)

    /// No offset leaves every side exactly where it was before the offset existed.
    @Test(arguments: NCPanelSide.allCases)
    func noOffset_isUnchanged(side: NCPanelSide) {
        #expect(CustomNCPanelController.xOffset(NCPanelOptions(side: side), on: screen) == 0)
    }

    @Test func offsetWithinRoom_isKept() {
        let o = NCPanelOptions(side: .right, xOffset: -300)
        #expect(CustomNCPanelController.xOffset(o, on: screen) == -300)
    }

    /// Too far either way stops with the rows as near the edge as the system's are.
    @Test func offsetPastEdge_stopsAtInset() {
        let width = CustomNCPanelController.rowWidth
        let inset = CustomNCPanelController.rightInset
        let left = CustomNCPanelController.xOffset(NCPanelOptions(side: .right, xOffset: -5000), on: screen)
        #expect(left == -(screen.width - 2 * inset - width))
        let right = CustomNCPanelController.xOffset(NCPanelOptions(side: .left, xOffset: 5000), on: screen)
        #expect(right == screen.width - 2 * inset - width)
        let stay = CustomNCPanelController.xOffset(NCPanelOptions(side: .right, xOffset: 200), on: screen)
        #expect(stay == 0)
    }

    /// A screen at an origin other than zero, as a second display is.
    @Test func secondDisplay_clampsToItsOwnEdges() {
        let other = NSRect(x: 1512, y: 0, width: 1920, height: 1080)
        let o = NCPanelOptions(side: .left, xOffset: -50)
        #expect(CustomNCPanelController.xOffset(o, on: other) == 0)
    }
}
