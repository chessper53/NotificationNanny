import CoreGraphics
import Testing
@testable import NotificationNannyCore

@Suite("Clock hit area")
struct ClockHitAreaTests {
    // AX frame of the clock on a 5120 pt wide display, measured on macOS 27.
    let clock = CGRect(x: 4963, y: 4, width: 134, height: 22)

    @Test func coversClicksMacOSSendsToTheClock() {
        let area = ClockOpeningShield.hitArea(of: clock, barTop: 0, screenRight: 5120)
        // Real clicks that opened the native panel without passing the old AX-frame check.
        for point in [CGPoint(x: 5119.9, y: 0), CGPoint(x: 5114, y: 6), CGPoint(x: 5105, y: 18),
                      CGPoint(x: 5017, y: 2), CGPoint(x: 4959, y: 20)] {
            #expect(area.contains(point), "\(point)")
        }
        #expect(!area.contains(CGPoint(x: 4950, y: 12)))
        #expect(!area.contains(CGPoint(x: 5050, y: 40)))
    }

    @Test func clockNotAtTheEdgeKeepsItsRightSide() {
        let area = ClockOpeningShield.hitArea(of: clock.offsetBy(dx: -200, dy: 0), barTop: 0, screenRight: 5120)
        #expect(!area.contains(CGPoint(x: 5000, y: 12)))
    }

    @Test func secondaryDisplayUsesItsOwnMenuBarTop() {
        let area = ClockOpeningShield.hitArea(of: clock.offsetBy(dx: 0, dy: -900), barTop: -904, screenRight: 5120)
        #expect(area.contains(CGPoint(x: 5100, y: -904)))
        #expect(!area.contains(CGPoint(x: 5100, y: 10)))
    }
}
