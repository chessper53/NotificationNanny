import AppKit
import Testing
@testable import NotificationNannyCore

/// A backup restores the configuration it was made from, all of it: every setting off its
/// default, exported, imported into a fresh install, and then every stored value compared.
/// Left out on purpose: whether it is on or snoozed right now, the apps it has learned,
/// and the two preferences about this Mac's own copy (menu bar icon, Settings appearance).
@Suite("Backup completeness") @MainActor
struct BackupCompletenessTests {
    private static let notInBackups: Set<String> = [
        "isEnabled", "snoozedUntil", "knownAppNames", "hideMenuBarIcon", "settingsAppearance", "lastBinaryMtime",
    ]

    private func makeSettings() -> (AppSettings, UserDefaults, String) {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        return (AppSettings(defaults: ud, knownAppsFileURL: url), ud, name)
    }

    @Test func everySettingSurvivesABackup() throws {
        let (s, sourceDefaults, sourceName) = makeSettings()
        if let screen = NSScreen.screens.first {
            s.setPlacement(ScreenPlacement(position: .topRight, xOffset: 12, yOffset: 34), for: screen)
        }
        // A screen that isn't connected: its stable key must come back as it was.
        s.targetDisplayID = 4242
        sourceDefaults.set("SCREEN-UUID-B", forKey: "targetDisplayUUID")
        s.autoDismissSeconds = 7
        s.bannerScale = 1.3
        s.bannerTint = BannerTint(r: 0.2, g: 0.4, b: 0.6)
        s.bannerTextTint = BannerTint(r: 0.9, g: 0.8, b: 0.1)
        s.bannerAnimation = .bounce
        s.holdWhileAsleep = true
        s.pauseWhileStreaming = true
        s.avoidNCPanel = false
        s.customNotificationCenter = true
        s.customNotificationCenterWidgets = true
        s.customNotificationCenterAppFilter = true
        s.customNotificationCenterAnimation = .drop
        s.customNotificationCenterScale = 1.2
        s.customNotificationCenterSide = .left
        s.customNotificationCenterDisplayID = 77
        s.customNotificationCenterTopOffset = 20
        s.customNotificationCenterXOffset = 40
        s.customNotificationCenterOwnBackground = true
        s.customNotificationCenterTint = BannerTint(r: 0.1, g: 0.2, b: 0.3)
        s.customNotificationCenterOwnText = true
        s.customNotificationCenterTextTint = BannerTint(r: 0.7, g: 0.7, b: 0.7)
        s.protectDesktopWidgets = false
        s.followActiveScreen = true
        s.pauseDuringFocus = true
        s.redactBannerContent = true
        s.newestBannerAtBottom = true
        s.allAppsSound = "Glass"
        s.allAppsSoundVolume = 0.4
        s.saveCurrentAsPreset(name: "Desk")
        s.flushPendingSaves()

        let (restored, restoredDefaults, restoredName) = makeSettings()
        try restored.importData(try s.exportData())
        restored.flushPendingSaves()

        let source = sourceDefaults.persistentDomain(forName: sourceName) ?? [:]
        let result = restoredDefaults.persistentDomain(forName: restoredName) ?? [:]
        for (key, value) in source where !Self.notInBackups.contains(key) {
            #expect((result[key] as? NSObject)?.isEqual(value) == true, "\(key) didn't come back from the backup")
        }
        #expect(restored.bannerTint == s.bannerTint)
        #expect(restored.bannerTextTint == s.bannerTextTint)
        #expect(restoredDefaults.string(forKey: "targetDisplayUUID") == "SCREEN-UUID-B")
    }

    /// A backup from before version 2 imports the settings it never had as their defaults.
    @Test func versionOneBackup_importsTheNewSettingsAsDefaults() throws {
        let backup = """
        {"schemaVersion": 1, "placements": {}, "targetDisplayID": 0, "autoDismissSeconds": 0, "bannerScale": 1.0,
         "pauseWhileStreaming": false, "appGroups": [], "presets": []}
        """.data(using: .utf8)!
        let (s, _, _) = makeSettings()
        s.bannerTint = BannerTint(r: 1, g: 0, b: 0)
        s.bannerAnimation = .bounce
        s.holdWhileAsleep = true
        try s.importData(backup)
        #expect(s.bannerTint == nil)
        #expect(s.bannerAnimation == .default)
        #expect(s.holdWhileAsleep == false)
    }
}
