import Foundation
import Testing
@testable import NotificationNannyCore

/// The Developer-tab "Apply a report" tool: parsing a pasted diagnostics report back into
/// live settings (behavior toggles, auto-dismiss, banner scale) for local reproduction.
@Suite("Apply report") @MainActor
struct ApplyReportTests {

    private func makeSettings() -> AppSettings {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        return AppSettings(defaults: ud, knownAppsFileURL: tempURL)
    }

    @Test func appliesBehaviorTogglesAutoDismissAndScale() {
        let s = makeSettings()
        let report = """
        [INFO]  Behavior: On: Hold while asleep, Follow active screen  •  Off: Protect desktop widgets, Avoid Notification Center panel, Pause while screen-sharing, Pause during Focus
        [INFO]  Auto-dismiss: 9s custom timeout
        [INFO]  Custom banner (global): Active — scale 175%
        """
        let changes = Diagnostics.applyReport(report, to: s)

        #expect(s.holdWhileAsleep == true)
        #expect(s.followActiveScreen == true)
        #expect(s.protectDesktopWidgets == false)
        #expect(s.avoidNCPanel == false)
        #expect(s.pauseWhileStreaming == false)
        #expect(s.pauseDuringFocus == false)
        #expect(s.autoDismissSeconds == 9)
        #expect(abs(s.bannerScale - 1.75) < 0.001)
        #expect(!changes.isEmpty)
    }

    @Test func systemDefaultAutoDismissParsesToZero() {
        let s = makeSettings()
        s.autoDismissSeconds = 5
        Diagnostics.applyReport("[INFO]  Auto-dismiss: System default", to: s)
        #expect(s.autoDismissSeconds == 0)
    }

    @Test func unrecognizedTextAppliesNothing() {
        let s = makeSettings()
        let before = s.holdWhileAsleep
        let changes = Diagnostics.applyReport("just some unrelated text", to: s)
        #expect(changes.isEmpty)
        #expect(s.holdWhileAsleep == before)
    }
}
