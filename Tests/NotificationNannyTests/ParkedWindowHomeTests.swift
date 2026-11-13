import CoreGraphics
import Testing
@testable import NotificationNannyCore

/// Where Notification Center's window goes back to when the app quits with it parked.
/// Screens in AX coordinates, the main one first.
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

    /// Hidden for a banner it keeps its x: back to the screen across from it.
    @Test func hiddenForBanner_backToItsScreen() {
        #expect(home(CGPoint(x: 6, y: -9999), size, [builtIn, dell]) == .zero)
        #expect(home(CGPoint(x: 2000, y: -9999), size, [builtIn, dell]) == CGPoint(x: 1710, y: 0))
        #expect(home(CGPoint(x: -1800, y: -9999), small, [builtIn, left]) == CGPoint(x: -1920, y: 0))
    }

    /// Parked for display sleep its x is gone too: the main screen.
    @Test func parkedForSleep_backToMain() {
        #expect(home(CGPoint(x: -9999, y: 0), size, [builtIn, dell]) == .zero)
    }

    /// Negative coordinates on a screen left of or above the main one are just a place.
    @Test func screensLeftAndAbove_areNotParked() {
        #expect(home(CGPoint(x: -1800, y: 50), small, [builtIn, left]) == nil)
        #expect(home(CGPoint(x: 100, y: -1200), small, [builtIn, above]) == nil)
    }

    /// Where a screen was unplugged, nothing is left to be on: back to the main one.
    @Test func disconnectedScreen_backToMain() {
        #expect(home(CGPoint(x: -1800, y: 50), small, [builtIn]) == .zero)
    }
}
