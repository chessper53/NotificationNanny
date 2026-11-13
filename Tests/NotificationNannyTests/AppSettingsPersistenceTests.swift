import AppKit
import Foundation
import Testing
@testable import NotificationNannyCore

// Reload through a separate instance to check persisted values rather than live memory.
@Suite("AppSettings persistence") @MainActor
struct AppSettingsPersistenceTests {

    private struct Store {
        let suiteName: String
        let fileURL: URL

        init() {
            suiteName = "NotificationNannyPersistTests_\(UUID().uuidString)"
            fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(suiteName).json")
        }

        @MainActor func make() -> AppSettings {
            AppSettings(defaults: UserDefaults(suiteName: suiteName)!,
                        knownAppsFileURL: fileURL)
        }

        @MainActor func cleanup() {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    @Test func isEnabled_persistsAcrossInit() {
        let store = Store(); defer { store.cleanup() }
        store.make().isEnabled = false
        #expect(store.make().isEnabled == false)
    }

    @Test func newestBannerAtBottom_defaultsOff_andPersists() {
        let store = Store(); defer { store.cleanup() }
        #expect(store.make().newestBannerAtBottom == false)
        store.make().newestBannerAtBottom = true
        #expect(store.make().newestBannerAtBottom == true)
    }

    @Test func ncPanelXOffset_missingKey_keepsSavedPlace() {
        let store = Store(); defer { store.cleanup() }
        let defaults = UserDefaults(suiteName: store.suiteName)!
        defaults.set("left", forKey: "customNotificationCenterSide")
        defaults.set(40.0, forKey: "customNotificationCenterTopOffset")
        let s = store.make()
        #expect(s.customNotificationCenterSide == .left)
        #expect(s.customNotificationCenterTopOffset == 40)
        #expect(s.customNotificationCenterXOffset == 0)
    }

    @Test func ncPanelXOffset_persistsAcrossInit() {
        let store = Store(); defer { store.cleanup() }
        store.make().customNotificationCenterXOffset = -120
        #expect(store.make().customNotificationCenterXOffset == -120)
    }

    @Test func autoDismissSeconds_persistsAcrossInit() {
        let store = Store(); defer { store.cleanup() }
        store.make().autoDismissSeconds = 42
        #expect(store.make().autoDismissSeconds == 42)
    }

    @Test func targetDisplayID_persistsAcrossInit() {
        let store = Store(); defer { store.cleanup() }
        store.make().targetDisplayID = 99
        #expect(store.make().targetDisplayID == 99)
    }

    // Flush debounced collections before constructing the reader instance.
    @Test func placements_persistAcrossInit() {
        guard let screen = NSScreen.main else { return }
        let store = Store(); defer { store.cleanup() }
        let written = ScreenPlacement(position: .bottomLeft, xOffset: 5, yOffset: -3)
        let a = store.make()
        a.setPlacement(written, for: screen)
        a.flushPendingSaves()
        let read = store.make().placement(for: screen)
        #expect(read.position == .bottomLeft)
        #expect(read.xOffset == 5)
        #expect(read.yOffset == -3)
    }

    // Legacy numeric display keys must migrate on first lookup.
    @Test func placements_migrateFromLegacyDisplayIDKey() throws {
        guard let screen = NSScreen.main else { return }
        let store = Store(); defer { store.cleanup() }
        let defaults = UserDefaults(suiteName: store.suiteName)!
        let legacy = ScreenPlacement(position: .bottomLeft, xOffset: 5, yOffset: -3)
        let legacyDict = [String(screen.displayID): legacy]
        defaults.set(try JSONEncoder().encode(legacyDict), forKey: "placementsByDisplayID")

        let settings = AppSettings(defaults: defaults, knownAppsFileURL: store.fileURL)
        #expect(settings.placement(for: screen) == legacy)

        // Reload to check that the migration was persisted.
        let reloaded = AppSettings(defaults: defaults, knownAppsFileURL: store.fileURL)
        #expect(reloaded.placement(for: screen) == legacy)
    }

    @Test func resolvedTargetScreen_matchesCurrentScreenViaStableKey() {
        guard let screen = NSScreen.main else { return }
        let store = Store(); defer { store.cleanup() }
        let settings = store.make()
        settings.targetDisplayID = screen.displayID
        #expect(settings.resolvedTargetScreen() === screen)
    }

    @Test func resolvedTargetScreen_nilWhenAuto() {
        let store = Store(); defer { store.cleanup() }
        let settings = store.make()
        settings.targetDisplayID = 0
        #expect(settings.resolvedTargetScreen() == nil)
    }

    // Backfill stable display keys at load time without requiring the user to select the screen
    // again.
    @Test func targetDisplayID_backfillsStableKeyOnInit() {
        guard let screen = NSScreen.main else { return }
        let store = Store(); defer { store.cleanup() }
        let defaults = UserDefaults(suiteName: store.suiteName)!
        defaults.set(Int(screen.displayID), forKey: "targetDisplayID")   // Legacy data has no UUID key.

        let settings = AppSettings(defaults: defaults, knownAppsFileURL: store.fileURL)
        #expect(settings.resolvedTargetScreen() === screen)
        #expect(defaults.string(forKey: "targetDisplayUUID") == screen.stableDisplayKey)
    }

    @Test func appGroup_backfillsStableKeyOnInit() throws {
        guard let screen = NSScreen.main else { return }
        let store = Store(); defer { store.cleanup() }
        let defaults = UserDefaults(suiteName: store.suiteName)!
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000002",
            "name": "Legacy",
            "appNames": [],
            "placement": {"position": "topRight", "xOffset": 0, "yOffset": 0},
            "targetDisplayID": \(screen.displayID)
        }
        """.data(using: .utf8)!
        let legacyGroup = try JSONDecoder().decode(AppGroup.self, from: json)
        #expect(legacyGroup.targetDisplayUUID == nil)
        defaults.set(try JSONEncoder().encode([legacyGroup]), forKey: "appGroups")

        let settings = AppSettings(defaults: defaults, knownAppsFileURL: store.fileURL)
        #expect(settings.appGroups.first?.targetDisplayUUID == screen.stableDisplayKey)
        #expect(settings.resolvedTargetScreen(forGroupID: legacyGroup.id) === screen)
    }

    @Test func presets_persistAcrossInit() {
        let store = Store(); defer { store.cleanup() }
        let a = store.make()
        a.autoDismissSeconds = 7
        a.saveCurrentAsPreset(name: "Night")
        let b = store.make()
        #expect(b.presets.count == 1)
        #expect(b.presets.first?.name == "Night")
        #expect(b.presets.first?.autoDismissSeconds == 7)
    }

    @Test func presets_multiplePresets_preserveOrder() {
        let store = Store(); defer { store.cleanup() }
        let a = store.make()
        a.saveCurrentAsPreset(name: "A")
        a.saveCurrentAsPreset(name: "B")
        a.saveCurrentAsPreset(name: "C")
        let b = store.make()
        #expect(b.presets.map(\.name) == ["A", "B", "C"])
    }

    @Test func appGroups_persistAcrossInit() {
        let store = Store(); defer { store.cleanup() }
        let a = store.make()
        let id = a.addGroup(name: "Work")
        a.addApp("Slack", toGroup: id)
        a.addApp("Zoom", toGroup: id)
        a.flushPendingSaves()
        let b = store.make()
        #expect(b.appGroups.count == 1)
        #expect(b.appGroups.first?.name == "Work")
        #expect(b.appGroups.first?.appNames == ["Slack", "Zoom"])
    }

    @Test func knownApps_persistToFileAcrossInit() {
        let store = Store(); defer { store.cleanup() }
        let a = store.make()
        a.recordAppName("Mail")
        a.recordAppName("Messages")
        let b = store.make()
        #expect(b.knownAppNames == ["Mail", "Messages"])
    }

    @Test func knownApps_fileURLTakesPrecedenceOverUserDefaults() {
        let store = Store(); defer { store.cleanup() }
        let a = store.make()
        a.recordAppName("Mail")
        // Simulate stale defaults alongside the newer file.
        UserDefaults(suiteName: store.suiteName)!.set(["Stale"], forKey: "knownAppNames")
        let b = store.make()
        #expect(b.knownAppNames == ["Mail"])
    }

    // MARK: Write coalescing

    @Test func placements_rapidWrites_coalesceIntoOneStore() {
        guard let screen = NSScreen.main else { return }
        let store = Store(); defer { store.cleanup() }
        let a = store.make()

        for i in 1...60 {
            a.setPlacement(ScreenPlacement(position: .topLeft, xOffset: Double(i), yOffset: 0),
                           for: screen)
        }
        // All 60 edits should still be pending in memory.
        #expect(UserDefaults(suiteName: store.suiteName)!
            .data(forKey: "placementsByDisplayID") == nil)

        a.flushPendingSaves()
        #expect(store.make().placement(for: screen).xOffset == 60)
    }

    @Test func placements_inMemoryValueIsImmediate() {
        guard let screen = NSScreen.main else { return }
        let store = Store(); defer { store.cleanup() }
        let a = store.make()
        // Only persistence is deferred; live placement must update immediately for dragging.
        a.setPlacement(ScreenPlacement(position: .bottomRight, xOffset: 7, yOffset: 9), for: screen)
        #expect(a.placement(for: screen).xOffset == 7)
        #expect(a.placement(for: screen).position == .bottomRight)
    }

    @Test func settingsAppearance_defaultsToSystem() {
        let store = Store(); defer { store.cleanup() }
        #expect(store.make().settingsAppearance == .system)
    }

    @Test func settingsAppearance_persistsAcrossInit() {
        let store = Store(); defer { store.cleanup() }
        store.make().settingsAppearance = .light
        #expect(store.make().settingsAppearance == .light)
        store.make().settingsAppearance = .dark
        #expect(store.make().settingsAppearance == .dark)
    }

    @Test func settingsAppearance_unknownStoredValue_fallsBackToSystem() {
        let store = Store(); defer { store.cleanup() }
        UserDefaults(suiteName: store.suiteName)!.set("sepia", forKey: "settingsAppearance")
        #expect(store.make().settingsAppearance == .system)
    }

    @Test func settingsAppearance_systemFollowsMacOS() {
        #expect(SettingsAppearance.system.nsAppearance == nil)
        #expect(SettingsAppearance.light.nsAppearance?.name == .aqua)
        #expect(SettingsAppearance.dark.nsAppearance?.name == .darkAqua)
    }
}
