import AppKit
import Testing
@testable import NotificationNannyCore

/// A backup restores the configuration it was made from, all of it: every setting off its
/// default, exported, imported into a fresh install, and then every stored value compared.
/// Left out on purpose: a snooze running, a countdown stale by any restore, and the app's
/// own bookkeeping.
@Suite("Backup completeness") @MainActor
struct BackupCompletenessTests {
    private static let notInBackups: Set<String> = ["snoozedUntil", "lastBinaryMtime"]

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
        // An exception group with its apps: matching goes by the group's own app names.
        let group = s.addGroup(name: "Work")
        s.addApp("Microsoft Teams", toGroup: group)
        s.addApp("Microsoft Outlook", toGroup: group)
        s.saveCurrentAsPreset(name: "Desk")
        s.isEnabled = false
        s.hideMenuBarIcon = true
        s.settingsAppearance = SettingsAppearance.allCases.first { $0 != s.settingsAppearance } ?? s.settingsAppearance
        s.recordAppName("Slack")
        s.recordAppName("Microsoft Teams")
        s.flushPendingSaves()

        let (restored, restoredDefaults, restoredName) = makeSettings()
        try restored.importData(try s.exportData())
        restored.flushPendingSaves()

        let source = sourceDefaults.persistentDomain(forName: sourceName) ?? [:]
        let result = restoredDefaults.persistentDomain(forName: restoredName) ?? [:]
        // Collections and colours are stored as JSON, whose key order varies from one
        // encoding to the next: compared by what they hold, not byte for byte.
        func content(_ value: Any?) -> NSObject? {
            if let data = value as? Data, let json = try? JSONSerialization.jsonObject(with: data) as? NSObject { return json }
            return value as? NSObject
        }
        for (key, value) in source where !Self.notInBackups.contains(key) {
            #expect(content(result[key])?.isEqual(content(value)) == true, "\(key) didn't come back from the backup")
        }
        // The apps seen come along, and both group apps' banners still go by the group.
        #expect(restored.knownAppNames == ["Microsoft Teams", "Slack"])
        #expect(restored.isEnabled == false)
        #expect(restored.hideMenuBarIcon == true)
        #expect(restored.settingsAppearance == s.settingsAppearance)
        #expect(restored.group(for: "Microsoft Teams")?.name == "Work")
        #expect(restored.group(for: "Microsoft Outlook")?.id == group)
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

/// Importing into an install that has seen other apps adds the backup's to them.
@Suite("Backup known apps") @MainActor
struct BackupKnownAppsTests {
    @Test func importMergesTheAppsSeen() throws {
        func make() -> AppSettings {
            let name = "NotificationNannyTests_\(UUID().uuidString)"
            return AppSettings(defaults: UserDefaults(suiteName: name)!,
                               knownAppsFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json"))
        }
        let source = make()
        source.recordAppName("Slack")
        let here = make()
        here.recordAppName("Mail")
        try here.importData(try source.exportData())
        #expect(here.knownAppNames == ["Mail", "Slack"])
    }

    /// A backup from before version 3 leaves them as they are.
    @Test func olderBackupKeepsWhatIsHere() throws {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        let s = AppSettings(defaults: UserDefaults(suiteName: name)!,
                            knownAppsFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json"))
        s.recordAppName("Mail")
        s.hideMenuBarIcon = true
        let backup = """
        {"schemaVersion": 2, "placements": {}, "targetDisplayID": 0, "autoDismissSeconds": 0, "bannerScale": 1.0,
         "pauseWhileStreaming": false, "appGroups": [], "presets": []}
        """.data(using: .utf8)!
        try s.importData(backup)
        #expect(s.knownAppNames == ["Mail"])
        #expect(s.hideMenuBarIcon == true)
    }
}

/// A backup is checked whole before any of it applies; one that can't be imported leaves
/// every setting as it was.
@Suite("Backup validation") @MainActor
struct BackupValidationTests {
    private func make() -> AppSettings {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        return AppSettings(defaults: UserDefaults(suiteName: name)!,
                           knownAppsFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json"))
    }
    private func backup(_ extra: String = "", scale: String = "1.0", version: Int = 3) -> Data {
        """
        {"schemaVersion": \(version), "placements": {}, "targetDisplayID": 0, "autoDismissSeconds": 0,
         "bannerScale": \(scale), "pauseWhileStreaming": false, "appGroups": [], "presets": []\(extra)}
        """.data(using: .utf8)!
    }

    @Test func notJSON_isRefused_andNothingChanges() {
        let s = make(); s.bannerScale = 1.3
        #expect(throws: AppSettings.BackupError.notABackup) { try s.importData(Data("hello".utf8)) }
        #expect(s.bannerScale == 1.3)
    }

    @Test func newerVersion_isRefused() {
        let s = make()
        #expect(throws: AppSettings.BackupError.newerVersion) { try s.importData(backup(version: 99)) }
    }

    @Test func outOfRangeValues_areRefused_andNothingChanges() {
        let s = make(); s.bannerScale = 1.3; s.redactBannerContent = true
        for bad in [backup(scale: "0"), backup(scale: "-1"), backup(scale: "40"),
                    backup(", \"customNotificationCenterScale\": 5"), backup(", \"allAppsSoundVolume\": 3"),
                    backup(", \"bannerTint\": {\"r\": 2, \"g\": 0, \"b\": 0}")] {
            #expect(throws: (any Error).self) { try s.importData(bad) }
        }
        #expect(s.bannerScale == 1.3)
        #expect(s.redactBannerContent == true)
    }

    @Test func validBackup_imports() throws {
        let s = make()
        try s.importData(backup(scale: "1.5"))
        #expect(s.bannerScale == 1.5)
    }
}

/// Reset All Settings: every setting as a fresh install has it.
@Suite("Reset all settings") @MainActor
struct ResetAllSettingsTests {
    @Test func resetMatchesAFreshInstall() throws {
        func make() -> AppSettings {
            let name = "NotificationNannyTests_\(UUID().uuidString)"
            return AppSettings(defaults: UserDefaults(suiteName: name)!,
                               knownAppsFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json"))
        }
        let s = make()
        s.bannerScale = 1.4; s.customNotificationCenter = true; s.customNotificationCenterWidgets = true
        s.pauseDuringFocus = true; s.pauseWhileStreaming = true; s.protectDesktopWidgets = false
        s.followActiveScreen = true; s.hideMenuBarIcon = true; s.redactBannerContent = true
        s.bannerTint = BannerTint(r: 1, g: 0, b: 0); s.saveCurrentAsPreset(name: "Desk")
        _ = s.addGroup(name: "Work")
        s.recordAppName("Slack")
        s.snooze(minutes: 30)
        s.resetAllSettings()

        let fresh = make()
        func backup(_ x: AppSettings) throws -> NSObject? {
            var json = try JSONSerialization.jsonObject(with: try x.exportData()) as? [String: Any]
            json?["knownAppNames"] = nil
            return json as NSObject?
        }
        #expect(try backup(s)?.isEqual(try backup(fresh)) == true)
        #expect(s.isSnoozed == false)
        // Learned, not set: kept.
        #expect(s.knownAppNames == ["Slack"])
    }
}
