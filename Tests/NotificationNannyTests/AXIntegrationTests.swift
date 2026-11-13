import Foundation
import AppKit
import Testing
@testable import NotificationNannyCore
import ApplicationServices

/// Run only when explicitly enabled; missing prerequisites must fail rather than silently skip
/// observations.
@Suite("AX integration (opt-in)", .enabled(if: ProcessInfo.processInfo.environment["NN_RUN_AX_TESTS"] == "1"))
@MainActor
struct AXIntegrationTests {

    @Test func observerMovesUniqueBanner() async throws {
        try #require(AXIsProcessTrusted(), "The test runner needs Accessibility permission")
        try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.notificationnanny.app").isEmpty,
                     "Quit NotificationNanny before running the live AX test")
        let nc = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first)
        try #require(!NSScreen.screens.isEmpty, "A graphical desktop is required")
        let suite = "NotificationNannyTests_AX_\(UUID().uuidString)"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: file)
        }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!, knownAppsFileURL: file)
        for screen in NSScreen.screens {
            settings.setPlacement(ScreenPlacement(position: .bottomLeft, xOffset: 0, yOffset: 0), for: screen)
        }
        let repositioner = NotificationRepositioner()
        repositioner.bind(to: settings)
        defer { repositioner.prepareForQuit() }
        for _ in 0..<20 where !repositioner.isObserving {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try #require(repositioner.isObserving, "Observer did not attach")

        let title = "NN-AX-\(UUID().uuidString)"
        TestNotification.sendCustom(title: title, body: "Live Accessibility integration test")
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var found: AXUIElement?
        defer { found?.performCustomAction(namedAnyOf: NCActionNames.close.union(NCActionNames.clearAll)) }
        func matchingBanner(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
            guard depth < 16 else { return nil }
            let subrole = element.stringAttribute(kAXSubroleAttribute as String) ?? ""
            if subrole.hasPrefix("AXNotificationCenter"), element.staticTextValues().contains(title) { return element }
            return element.children().lazy.compactMap { matchingBanner($0, depth: depth + 1) }.first
        }
        var moved = false
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 200_000_000)
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
            found = (value as? [AXUIElement] ?? []).lazy.compactMap { matchingBanner($0) }.first ?? found
            guard let banner = found, let position = banner.point(), let size = banner.size() else { continue }
            moved = NSScreen.screens.contains { screen in
                let expected = NotificationPosition.bottomLeft.axOrigin(forWindowSize: size, screen: screen, xOffset: 0, yOffset: 0)
                return abs(position.x - expected.x) <= 12 && abs(position.y - expected.y) <= 12
            }
            if moved { break }
        }
        #expect(moved, "Unique banner never reached bottom-left; a send log is insufficient")
    }
}
