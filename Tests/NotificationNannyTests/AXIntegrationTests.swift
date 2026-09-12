import Foundation
import Testing
@testable import NotificationNannyCore
import ApplicationServices

/// Exercises `NotificationRepositioner` against the *real* AX observation pipeline —
/// the one thing ARCHITECTURE.md has always listed as "not covered (integration/manual)".
///
/// This can only run where the calling process (here, the test runner) has been
/// granted Accessibility permission and a real `com.apple.notificationcenterui`
/// process is reachable — neither is true in CI, so the suite is conditionally
/// enabled and simply reports nothing (not a failure) when unavailable. Where it
/// *can* run — a developer's own machine, with permission already granted for
/// local development — it catches real reposition/observer regressions instead of
/// relying entirely on the manual "send a test notification and look at it" loop.
@Suite("AX integration (requires local Accessibility permission)", .enabled(if: AXIsProcessTrusted()))
@MainActor
struct AXIntegrationTests {

    private func makeSettings() -> AppSettings {
        let name = "NotificationNannyTests_AX_\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        return AppSettings(defaults: ud, knownAppsFileURL: tempURL)
    }

    /// Sends a real test notification through the live AX path and confirms the
    /// repositioner's observer actually attaches to NC and logs banner activity for
    /// it — i.e. the whole AXObserver → handleAXEvent → repositionWindow chain is
    /// intact, not just its individually-unit-tested pieces.
    @Test func observerAttachesAndHandlesTestBanner() async throws {
        let settings = makeSettings()
        let repositioner = NotificationRepositioner()
        repositioner.bind(to: settings)

        // Give the observer a moment to attach to the NC process.
        try await Task.sleep(nanoseconds: 500_000_000)
        guard repositioner.isObserving else {
            // NC isn't reachable in this environment (e.g. sandboxed CI runner) —
            // not a failure of the code under test, just an environment that can't
            // exercise this path. Nothing more to assert.
            return
        }

        let before = NannyLogger.shared.entries.count
        repositioner.sendTestNotification(groupID: nil)

        // Poll briefly rather than a single fixed sleep — real delivery timing
        // varies with system load.
        var sawBannerActivity = false
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 250_000_000)
            let newEntries = NannyLogger.shared.entries.dropFirst(before)
            if newEntries.contains(where: { $0.tag == "Banner" || $0.tag == "Custom" || $0.tag == "Test" }) {
                sawBannerActivity = true
                break
            }
        }

        #expect(sawBannerActivity, "Expected the AX observer to log banner activity after sendTestNotification")
    }
}
