import AppKit
import Foundation
import Testing
@testable import NotificationNannyCore

// Tests the axOrigin coordinate maths. AX coordinates have y=0 at the top-left
// of the primary screen, y increasing downward — the opposite of NSScreen's
// flipped-y convention. These tests pin the transformation so a sign flip or
// off-by-one is immediately visible.
@Suite("NotificationPosition geometry") @MainActor
struct NotificationPositionGeometryTests {

    private let size = CGSize(width: 100, height: 50)
    private let inset: CGFloat = 8  // matches the private safeInset constant

    private func o(_ pos: NotificationPosition,
                   screen: NSScreen,
                   x: CGFloat = 0, y: CGFloat = 0) -> CGPoint {
        pos.axOrigin(forWindowSize: size, screen: screen, xOffset: x, yOffset: y)
    }

    // MARK: - Ordering

    @Test func leftColumn_hasSmallestX_rightColumn_hasLargestX() throws {
        let screen = try #require(NSScreen.main)
        let rows: [(NotificationPosition, NotificationPosition, NotificationPosition)] = [
            (.topLeft,    .topCenter,    .topRight),
            (.middleLeft, .middleCenter, .middleRight),
            (.bottomLeft, .bottomCenter, .bottomRight),
        ]
        for (l, c, r) in rows {
            #expect(o(l, screen: screen).x < o(c, screen: screen).x, "left < center for \(l)")
            #expect(o(c, screen: screen).x < o(r, screen: screen).x, "center < right for \(c)")
        }
    }

    @Test func topRow_hasSmallestY_bottomRow_hasLargestY() throws {
        let screen = try #require(NSScreen.main)
        let cols: [(NotificationPosition, NotificationPosition, NotificationPosition)] = [
            (.topLeft,   .middleLeft,   .bottomLeft),
            (.topCenter, .middleCenter, .bottomCenter),
            (.topRight,  .middleRight,  .bottomRight),
        ]
        for (t, m, b) in cols {
            #expect(o(t, screen: screen).y < o(m, screen: screen).y, "top < middle for \(t)")
            #expect(o(m, screen: screen).y < o(b, screen: screen).y, "middle < bottom for \(m)")
        }
    }

    // MARK: - Same row / column alignment

    @Test func sameColumn_samexCoordinate() throws {
        let screen = try #require(NSScreen.main)
        let cols: [(NotificationPosition, NotificationPosition, NotificationPosition)] = [
            (.topLeft,   .middleLeft,   .bottomLeft),
            (.topRight,  .middleRight,  .bottomRight),
            (.topCenter, .middleCenter, .bottomCenter),
        ]
        for (a, b, c) in cols {
            #expect(o(a, screen: screen).x == o(b, screen: screen).x, "x mismatch: \(a)/\(b)")
            #expect(o(b, screen: screen).x == o(c, screen: screen).x, "x mismatch: \(b)/\(c)")
        }
    }

    @Test func sameRow_sameYCoordinate() throws {
        let screen = try #require(NSScreen.main)
        let rows: [(NotificationPosition, NotificationPosition, NotificationPosition)] = [
            (.topLeft,    .topCenter,    .topRight),
            (.middleLeft, .middleCenter, .middleRight),
            (.bottomLeft, .bottomCenter, .bottomRight),
        ]
        for (a, b, c) in rows {
            #expect(o(a, screen: screen).y == o(b, screen: screen).y, "y mismatch: \(a)/\(b)")
            #expect(o(b, screen: screen).y == o(c, screen: screen).y, "y mismatch: \(b)/\(c)")
        }
    }

    // MARK: - Offset linearity

    @Test func xOffset_shiftsXByExactAmount() throws {
        let screen = try #require(NSScreen.main)
        let base    = o(.topRight, screen: screen, x: 0,  y: 0)
        let shifted = o(.topRight, screen: screen, x: 20, y: 0)
        #expect(shifted.x == base.x + 20)
        #expect(shifted.y == base.y)
    }

    @Test func yOffset_shiftsYByExactAmount() throws {
        let screen = try #require(NSScreen.main)
        let base    = o(.topRight, screen: screen, x: 0, y: 0)
        let shifted = o(.topRight, screen: screen, x: 0, y: 15)
        #expect(shifted.x == base.x)
        #expect(shifted.y == base.y + 15)
    }

    @Test func negativeOffset_shiftsInOppositeDirection() throws {
        let screen = try #require(NSScreen.main)
        let base    = o(.bottomRight, screen: screen, x:   0, y:   0)
        let shifted = o(.bottomRight, screen: screen, x: -10, y: -5)
        #expect(shifted.x == base.x - 10)
        #expect(shifted.y == base.y - 5)
    }

    // MARK: - Exact coordinate formula
    //
    // These hardcode the expected values derived from the formula so that any
    // refactor that silently changes the coordinate mapping fails immediately.

    @Test func topRight_matchesExpectedFormula() throws {
        let screen  = try #require(NSScreen.main)
        let primary = try #require(NSScreen.screens.first)
        let visible = screen.visibleFrame
        let expectedX = visible.maxX - inset - size.width
        let expectedY = primary.frame.height - visible.maxY + inset
        let p = o(.topRight, screen: screen)
        #expect(p.x == expectedX)
        #expect(p.y == expectedY)
    }

    @Test func bottomLeft_matchesExpectedFormula() throws {
        let screen  = try #require(NSScreen.main)
        let primary = try #require(NSScreen.screens.first)
        let visible = screen.visibleFrame
        let expectedX = visible.minX + inset
        let expectedY = primary.frame.height - visible.minY - inset - size.height
        let p = o(.bottomLeft, screen: screen)
        #expect(p.x == expectedX)
        #expect(p.y == expectedY)
    }

    @Test func middleCenter_isCenteredInAxVisibleFrame() throws {
        let screen  = try #require(NSScreen.main)
        let primary = try #require(NSScreen.screens.first)
        let visible = screen.visibleFrame
        let axLeft   = visible.minX + inset
        let axRight  = visible.maxX - inset
        let axTop    = primary.frame.height - visible.maxY + inset
        let axBottom = primary.frame.height - visible.minY - inset
        let expectedX = axLeft + ((axRight  - axLeft)  - size.width)  / 2
        let expectedY = axTop  + ((axBottom - axTop)   - size.height) / 2
        let p = o(.middleCenter, screen: screen)
        #expect(p.x == expectedX)
        #expect(p.y == expectedY)
    }
}
