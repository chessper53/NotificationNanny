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

/// A capture of nothing never replaces a widget's picture.
@Suite("Widget capture blank check")
struct WidgetBlankTests {
    private func image(_ draw: (CGContext) -> Void) -> CGImage {
        let c = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(c)
        return c.makeImage()!
    }

    @Test func oneColour_isBlank() {
        let gray = image { $0.setFillColor(gray: 0.3, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
        #expect(WidgetCapture.isBlank(gray))
    }

    @Test func content_isNot() {
        let drawn = image {
            $0.setFillColor(gray: 0.2, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            $0.setFillColor(gray: 0.9, alpha: 1); $0.fill(CGRect(x: 10, y: 10, width: 30, height: 20))
        }
        #expect(!WidgetCapture.isBlank(drawn))
    }
}
