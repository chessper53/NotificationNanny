import CoreGraphics
import Testing
@testable import NotificationNannyCore

/// Where the real panel's window waits, drawn but unseen, while ours shows its widgets:
/// above the highest screen with only its bottom row on it. Screens in AX coordinates.
@Suite("NC widget placement") @MainActor
struct NCWidgetPlacementTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1710, height: 1107)

    @Test func oneScreen_bottomRowOnItsTopEdge() {
        let origin = NCPanelTakeover.drawnOffScreen(windowSize: builtIn.size, screens: [builtIn])
        #expect(origin == CGPoint(x: 0, y: -1106))
    }

    /// A wider screen beside it, tops aligned (the built-in and an external one): the row
    /// lies along both tops, and nothing of the rest is on either.
    @Test func screenBeside_stillUnseen() {
        let dell = CGRect(x: 1710, y: 0, width: 3440, height: 1440)
        let origin = NCPanelTakeover.drawnOffScreen(windowSize: builtIn.size, screens: [builtIn, dell])
        #expect(origin == CGPoint(x: 0, y: -1106))
    }

    /// A screen arranged above: the window goes above that one instead.
    @Test func screenAbove_goesAboveIt() {
        let above = CGRect(x: 200, y: -1440, width: 2560, height: 1440)
        let origin = NCPanelTakeover.drawnOffScreen(windowSize: builtIn.size, screens: [builtIn, above])
        #expect(origin == CGPoint(x: 200, y: -1440 - 1106))
    }

    @Test func noScreens_nowhere() {
        #expect(NCPanelTakeover.drawnOffScreen(windowSize: builtIn.size, screens: []) == nil)
    }
}
