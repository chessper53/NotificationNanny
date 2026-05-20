import AppKit
import Foundation
import Testing
@testable import NotificationNannyCore

// Verifies that each persisted field survives a fresh AppSettings init from
// the same backing storage. Mutations go to instance A; reads come from
// instance B constructed afterwards from the identical UserDefaults suite
// and file URL — so any bug in didSet serialisation or init deserialisation fails here.
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

    @Test func placements_persistAcrossInit() {
        guard let screen = NSScreen.main else { return }
        let store = Store(); defer { store.cleanup() }
        let written = ScreenPlacement(position: .bottomLeft, xOffset: 5, yOffset: -3)
        store.make().setPlacement(written, for: screen)
        let read = store.make().placement(for: screen)
        #expect(read.position == .bottomLeft)
        #expect(read.xOffset == 5)
        #expect(read.yOffset == -3)
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
        // Write names through the normal path (goes to both UserDefaults and file).
        let a = store.make()
        a.recordAppName("Mail")
        // Now write different data directly into UserDefaults (simulating stale data).
        UserDefaults(suiteName: store.suiteName)!.set(["Stale"], forKey: "knownAppNames")
        // The next init should prefer the file over UserDefaults.
        let b = store.make()
        #expect(b.knownAppNames == ["Mail"])
    }
}
