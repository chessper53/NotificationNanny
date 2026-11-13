import CoreGraphics
import Testing
@testable import NotificationNannyCore

/// Fixtures use AX coordinates with the main screen first.
@Suite("Parked window home") @MainActor
struct ParkedWindowHomeTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    private let dell = CGRect(x: 1710, y: 0, width: 3440, height: 1440)
    private let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    private let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
    private let size = CGSize(width: 1710, height: 1107)
    private let small = CGSize(width: 360, height: 120)

    private func home(_ p: CGPoint, _ s: CGSize, _ screens: [CGRect]) -> CGPoint? {
        NotificationRepositioner.homeOrigin(forParked: p, size: s, screens: screens)
    }

    @Test func onScreen_staysPut() {
        #expect(home(CGPoint(x: 6, y: 0), size, [builtIn, dell]) == nil)
    }

    @Test func hiddenForBanner_backToItsScreen() {
        #expect(home(CGPoint(x: 6, y: -9999), size, [builtIn, dell]) == .zero)
        #expect(home(CGPoint(x: 2000, y: -9999), size, [builtIn, dell]) == CGPoint(x: 1710, y: 0))
        #expect(home(CGPoint(x: -1800, y: -9999), small, [builtIn, left]) == CGPoint(x: -1920, y: 0))
    }

    @Test func parkedForSleep_backToMain() {
        #expect(home(CGPoint(x: -9999, y: 0), size, [builtIn, dell]) == .zero)
    }

    @Test func screensLeftAndAbove_areNotParked() {
        #expect(home(CGPoint(x: -1800, y: 50), small, [builtIn, left]) == nil)
        #expect(home(CGPoint(x: 100, y: -1200), small, [builtIn, above]) == nil)
    }

    @Test func sliverOnScreen_isParked() {
        let wide = CGSize(width: 5120, height: 1440)
        let odyssey = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        #expect(home(CGPoint(x: 0, y: -1439), wide, [odyssey]) == .zero)
    }

    @Test func disconnectedScreen_backToMain() {
        #expect(home(CGPoint(x: -1800, y: 50), small, [builtIn]) == .zero)
    }
}
