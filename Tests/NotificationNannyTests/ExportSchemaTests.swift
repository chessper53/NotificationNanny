import Foundation
import Testing
@testable import NotificationNannyCore

/// Backup export/import: schema versioning and forward/backward compatibility of
/// the optional toggles added over time (`protectDesktopWidgets`,
/// `pauseDuringFocus`, `followActiveScreen`).
@Suite("Export schema") @MainActor
struct ExportSchemaTests {

    private func makeSettings() -> AppSettings {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        return AppSettings(defaults: ud, knownAppsFileURL: tempURL)
    }

    @Test func export_stampsCurrentSchemaVersion() throws {
        let s = makeSettings()
        let data = try s.exportData()
        let decoded = try JSONDecoder().decode(AppSettings.SettingsExport.self, from: data)
        #expect(decoded.schemaVersion == AppSettings.currentExportSchemaVersion)
    }

    @Test func roundTrip_preservesToggles() throws {
        let s = makeSettings()
        s.bannerScale = 1.8
        s.autoDismissSeconds = 12
        s.targetDisplayID = 7
        s.protectDesktopWidgets = false
        s.pauseDuringFocus = true
        s.followActiveScreen = true
        s.pauseWhileStreaming = true

        let data = try s.exportData()

        let restored = makeSettings()
        try restored.importData(data)

        #expect(restored.bannerScale == 1.8)
        #expect(restored.autoDismissSeconds == 12)
        #expect(restored.targetDisplayID == 7)
        #expect(restored.protectDesktopWidgets == false)
        #expect(restored.pauseDuringFocus == true)
        #expect(restored.followActiveScreen == true)
        #expect(restored.pauseWhileStreaming == true)
    }

    /// A backup written before these toggles (and before schema versioning) must
    /// import cleanly, restoring the documented defaults for the absent fields.
    @Test func import_legacyBackup_appliesDefaults() throws {
        let legacy = """
        {
            "placements": {},
            "targetDisplayID": 0,
            "autoDismissSeconds": 0,
            "bannerScale": 1.0,
            "pauseWhileStreaming": false,
            "avoidNCPanel": true,
            "appGroups": [],
            "presets": []
        }
        """.data(using: .utf8)!

        let s = makeSettings()
        s.protectDesktopWidgets = false   // ensure import resets it, not leaves stale
        s.pauseDuringFocus = true
        try s.importData(legacy)

        #expect(s.protectDesktopWidgets == true)   // default when absent
        #expect(s.pauseDuringFocus == false)       // default when absent
        #expect(s.followActiveScreen == false)     // default when absent
    }

    /// A backup from a hypothetical newer schema must still import the fields we
    /// understand (unknown keys are ignored by JSONDecoder).
    @Test func import_newerSchema_stillApplied() throws {
        let future = """
        {
            "schemaVersion": 999,
            "placements": {},
            "targetDisplayID": 3,
            "autoDismissSeconds": 5,
            "bannerScale": 2.0,
            "pauseWhileStreaming": false,
            "avoidNCPanel": true,
            "protectDesktopWidgets": false,
            "pauseDuringFocus": true,
            "appGroups": [],
            "presets": [],
            "someUnknownFutureField": 42
        }
        """.data(using: .utf8)!

        let s = makeSettings()
        try s.importData(future)

        #expect(s.targetDisplayID == 3)
        #expect(s.bannerScale == 2.0)
        #expect(s.protectDesktopWidgets == false)
        #expect(s.pauseDuringFocus == true)
    }
}
