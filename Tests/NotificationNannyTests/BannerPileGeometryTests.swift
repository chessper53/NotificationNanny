import AppKit
import Foundation
import Testing
@testable import NotificationNannyCore

// Placement of a pile of banners (#39). Since macOS 26 banners that are up
// together share one host, newest on top, and they are placed as one block:
// growing upward from a bottom corner, and kept on screen as a whole.
@Suite("Banner pile geometry") @MainActor
struct BannerPileGeometryTests {

    private let frame = CGRect(x: 0, y: 25, width: 1000, height: 700)   // AX coords, below a menu bar
    private let banner = CGSize(width: 344, height: 58)

    // MARK: - clamp

    @Test func clamp_leavesARectThatFits() {
        let p = CGPoint(x: 100, y: 200)
        #expect(NotificationPosition.clamp(p, size: banner, into: frame) == p)
    }

    @Test func clamp_pastTheBottom_movesUpJustEnough() {
        let p = NotificationPosition.clamp(CGPoint(x: 100, y: 700), size: banner, into: frame)
        #expect(p.y == frame.maxY - banner.height)
        #expect(p.x == 100)
    }

    @Test func clamp_pastTheRight_movesLeftJustEnough() {
        let p = NotificationPosition.clamp(CGPoint(x: 900, y: 100), size: banner, into: frame)
        #expect(p.x == frame.maxX - banner.width)
    }

    @Test func clamp_aboveTheTop_movesDown() {
        let p = NotificationPosition.clamp(CGPoint(x: 100, y: -40), size: banner, into: frame)
        #expect(p.y == frame.minY)
    }

    /// A pile taller than the screen keeps its top, the newest banner, in view.
    @Test func clamp_tallerThanTheFrame_keepsTheTop() {
        let tall = CGSize(width: 344, height: 900)
        let p = NotificationPosition.clamp(CGPoint(x: 100, y: 300), size: tall, into: frame)
        #expect(p.y == frame.minY)
    }

    // MARK: - axStackOrigin

    /// Bottom positions place the pile's bottom where a single banner's bottom
    /// would be, so it grows upward.
    @Test func bottomPositions_growUpward() throws {
        let screen = try #require(NSScreen.main)
        for pos: NotificationPosition in [.bottomLeft, .bottomCenter, .bottomRight] {
            let one = pos.axOrigin(forWindowSize: banner, screen: screen, xOffset: 0, yOffset: 0)
            let pile = CGSize(width: banner.width, height: 3 * banner.height + 12)
            let o = pos.axStackOrigin(stackSize: pile, screen: screen, xOffset: 0, yOffset: 0)
            #expect(o.y + pile.height == one.y + banner.height, "bottom edge stays for \(pos)")
            #expect(o.y < one.y, "pile grows upward for \(pos)")
        }
    }

    /// Top positions keep the first banner where it always was; the pile grows down.
    @Test func topPositions_keepTheFirstBannerInPlace() throws {
        let screen = try #require(NSScreen.main)
        for pos: NotificationPosition in [.topLeft, .topCenter, .topRight] {
            let one = pos.axOrigin(forWindowSize: banner, screen: screen, xOffset: 0, yOffset: 0)
            let pile = CGSize(width: banner.width, height: 3 * banner.height + 12)
            #expect(pos.axStackOrigin(stackSize: pile, screen: screen, xOffset: 0, yOffset: 0).y == one.y)
        }
    }

    /// A single banner within the screen lands exactly where it did before piles.
    /// (Offsets stay inside the 8 pt built-in inset, so nothing needs clamping.)
    @Test func singleBanner_unchangedWhenOnScreen() throws {
        let screen = try #require(NSScreen.main)
        for pos in NotificationPosition.allCases {
            for (x, y) in [(-5.0, -5.0), (5, 5)] as [(CGFloat, CGFloat)] {
                let one = pos.axOrigin(forWindowSize: banner, screen: screen, xOffset: x, yOffset: y)
                #expect(pos.axStackOrigin(stackSize: banner, screen: screen, xOffset: x, yOffset: y) == one, "\(pos) (\(x),\(y))")
            }
        }
    }

    /// The reported setup: bottom right, pushed up by an offset. The pile grows
    /// up from that spot, and an offset pushing it past an edge is pulled back.
    @Test func offsets_neverPushThePileOffScreen() throws {
        let screen = try #require(NSScreen.main)
        let visible = NotificationPosition.axVisibleFrame(of: screen)
        let pile = CGSize(width: banner.width, height: 4 * banner.height + 18)
        for pos in NotificationPosition.allCases {
            for (x, y) in [(0.0, -205.0), (0, 400), (0, -4000), (3000, 0), (-3000, 0)] as [(CGFloat, CGFloat)] {
                let o = pos.axStackOrigin(stackSize: pile, screen: screen, xOffset: x, yOffset: y)
                let rect = CGRect(origin: o, size: pile)
                #expect(visible.insetBy(dx: -0.5, dy: -0.5).contains(rect), "\(pos) offset (\(x),\(y)) → \(rect)")
            }
        }
    }

    @Test func axVisibleFrame_isInsideTheScreen() throws {
        let screen = try #require(NSScreen.main)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let full = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                          width: screen.frame.width, height: screen.frame.height)
        #expect(full.contains(NotificationPosition.axVisibleFrame(of: screen)))
    }
}
