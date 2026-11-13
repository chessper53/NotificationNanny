import AppKit
import Testing
@testable import NotificationNannyCore

@Suite("NC panel offset") @MainActor
struct NCPanelOffsetTests {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)

    @Test(arguments: NCPanelSide.allCases)
    func noOffset_isUnchanged(side: NCPanelSide) {
        #expect(CustomNCPanelController.xOffset(NCPanelOptions(side: side), on: screen) == 0)
    }

    @Test func offsetWithinRoom_isKept() {
        let o = NCPanelOptions(side: .right, xOffset: -300)
        #expect(CustomNCPanelController.xOffset(o, on: screen) == -300)
    }

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

    @Test func secondDisplay_clampsToItsOwnEdges() {
        let other = NSRect(x: 1512, y: 0, width: 1920, height: 1080)
        let o = NCPanelOptions(side: .left, xOffset: -50)
        #expect(CustomNCPanelController.xOffset(o, on: other) == 0)
    }
}
