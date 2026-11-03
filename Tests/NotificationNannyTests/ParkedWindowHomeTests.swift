import CoreGraphics
import Testing
@testable import NotificationNannyCore

/// Where Notification Center's window goes back to when the app quits with it parked.
/// Screens in AX coordinates, the main one first.
@Suite("Parked window home") @MainActor
struct ParkedWindowHomeTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    private let dell = CGRect(x: 1710, y: 0, width: 3440, height: 1440)

    @Test func onScreen_staysPut() {
        #expect(NotificationRepositioner.homeOrigin(forParked: CGPoint(x: 6, y: 0), screens: [builtIn, dell]) == nil)
    }

    /// Hidden for a banner it keeps its x: back to the screen across from it.
    @Test func hiddenForBanner_backToItsScreen() {
        #expect(NotificationRepositioner.homeOrigin(forParked: CGPoint(x: 6, y: -9999), screens: [builtIn, dell]) == .zero)
        #expect(NotificationRepositioner.homeOrigin(forParked: CGPoint(x: 2000, y: -9999), screens: [builtIn, dell])
                == CGPoint(x: 1710, y: 0))
    }

    /// Parked for display sleep its x is gone too: the main screen.
    @Test func parkedForSleep_backToMain() {
        #expect(NotificationRepositioner.homeOrigin(forParked: CGPoint(x: -9999, y: 0), screens: [builtIn, dell]) == .zero)
    }
}
