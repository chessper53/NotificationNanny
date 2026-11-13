import Foundation
import Testing
@testable import NotificationNannyCore

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

    @Test func roundTrip_preservesPanelToggle() throws {
        let s = makeSettings()
        s.avoidNCPanel = false
        let restored = makeSettings()
        try restored.importData(try s.exportData())
        #expect(restored.avoidNCPanel == false)
    }

    @Test func import_withoutPanelToggle_defaultsOn() throws {
        let backup = """
        {"placements": {}, "targetDisplayID": 0, "autoDismissSeconds": 0, "bannerScale": 1.0,
         "pauseWhileStreaming": false, "appGroups": [], "presets": []}
        """.data(using: .utf8)!
        let s = makeSettings()
        s.avoidNCPanel = false
        try s.importData(backup)
        #expect(s.avoidNCPanel == true)
    }

    @Test func ncPanelXOffset_roundTrips_andDefaultsToZero() throws {
        let s = makeSettings()
        s.customNotificationCenterXOffset = 85
        let restored = makeSettings()
        try restored.importData(try s.exportData())
        #expect(restored.customNotificationCenterXOffset == 85)

        let backup = """
        {"placements": {}, "targetDisplayID": 0, "autoDismissSeconds": 0, "bannerScale": 1.0,
         "pauseWhileStreaming": false, "customNotificationCenterSide": "left",
         "customNotificationCenterTopOffset": 30, "appGroups": [], "presets": []}
        """.data(using: .utf8)!
        try restored.importData(backup)
        #expect(restored.customNotificationCenterSide == .left)
        #expect(restored.customNotificationCenterTopOffset == 30)
        #expect(restored.customNotificationCenterXOffset == 0)
    }

    /// Ignore the retired times switch while importing the rest of a legacy backup.
    @Test func import_withOldTimesSwitch_appliesTheRest() throws {
        let backup = """
        {"placements": {}, "targetDisplayID": 0, "autoDismissSeconds": 0, "bannerScale": 1.0,
         "pauseWhileStreaming": false, "customNotificationCenter": true, "customNotificationCenterTimes": true,
         "customNotificationCenterAppFilter": true, "appGroups": [], "presets": []}
        """.data(using: .utf8)!
        let s = makeSettings()
        try s.importData(backup)
        #expect(s.customNotificationCenter)
        #expect(s.customNotificationCenterAppFilter)
    }

    /// The tab move must not alter persisted exception group data.
    @Test func groupsSavedForExceptionsTab_readBackUnchanged() throws {
        let backup = """
        {"placements": {}, "targetDisplayID": 0, "autoDismissSeconds": 0, "bannerScale": 1.0,
         "pauseWhileStreaming": false, "presets": [], "appGroups": [
          {"id":"D9F9B277-0783-49F6-9B3B-F3D6B8C55828","name":"Prio","targetDisplayID":0,
           "bannerTint":{"r":1,"g":0,"b":0.79},"bannerScale":1.19,"appNames":["Microsoft Teams","WhatsApp"],
           "placement":{"position":"topLeft","yOffset":0,"xOffset":241.5}},
          {"bannerAnimation":"Rise","id":"7D66090F-CB99-4F34-BCC2-C1271EAAA687","name":"Outlook",
           "targetDisplayID":3,"bannerScale":1,"appNames":["Code","Microsoft Outlook"],
           "placement":{"position":"bottomRight","yOffset":0,"xOffset":0}}]}
        """.data(using: .utf8)!
        let s = makeSettings()
        try s.importData(backup)
        #expect(s.appGroups.count == 2)
        let prio = try #require(s.appGroups.first { $0.name == "Prio" })
        #expect(prio.appNames == ["Microsoft Teams", "WhatsApp"])
        #expect(prio.bannerScale == 1.19)
        #expect(prio.bannerTint == BannerTint(r: 1, g: 0, b: 0.79))
        #expect(prio.bannerAnimation == nil)
        #expect(prio.placement.position == .topLeft && prio.placement.xOffset == 241.5)
        let outlook = try #require(s.appGroups.first { $0.name == "Outlook" })
        #expect(outlook.targetDisplayID == 3)
        #expect(outlook.bannerScale == 1)
        #expect(outlook.bannerTint == nil)
        #expect(outlook.bannerAnimation == .rise)
        #expect(outlook.placement.position == .bottomRight)

        let again = makeSettings()
        try again.importData(try s.exportData())
        #expect(again.appGroups == s.appGroups)
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
        s.newestBannerAtBottom = true

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
        #expect(restored.newestBannerAtBottom == true)
    }

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
        s.protectDesktopWidgets = false
        s.pauseDuringFocus = true
        s.newestBannerAtBottom = true
        try s.importData(legacy)

        #expect(s.protectDesktopWidgets == true)
        #expect(s.pauseDuringFocus == false)
        #expect(s.followActiveScreen == false)
        #expect(s.newestBannerAtBottom == false)
    }

    @Test func import_newerSchema_isRefused() throws {
        let future = """
        {"schemaVersion": 999, "placements": {}, "targetDisplayID": 3, "autoDismissSeconds": 5,
         "bannerScale": 2.0, "pauseWhileStreaming": false, "appGroups": [], "presets": []}
        """.data(using: .utf8)!
        let s = makeSettings()
        s.autoDismissSeconds = 0
        #expect(throws: AppSettings.BackupError.newerVersion) { try s.importData(future) }
        #expect(s.autoDismissSeconds == 0)
    }
}
