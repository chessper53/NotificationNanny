import Foundation
import Testing
@testable import NotificationNannyCore

// AppSettings is @MainActor, so each test helper creates its own isolated
// instance with a throwaway UserDefaults suite.
@Suite("AppSettings") @MainActor
struct AppSettingsTests {

    private func makeSettings() -> (AppSettings, String) {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        return (AppSettings(defaults: ud, knownAppsFileURL: tempURL), name)
    }

    // MARK: - Group CRUD

    @Test func addGroup_appendsGroup() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "Work")
        #expect(s.appGroups.count == 1)
        #expect(s.appGroups.first?.id == id)
        #expect(s.appGroups.first?.name == "Work")
    }

    @Test func deleteGroup_removesCorrectGroup() {
        let (s, _) = makeSettings()
        let a = s.addGroup(name: "A")
        let b = s.addGroup(name: "B")
        s.deleteGroup(a)
        #expect(s.appGroups.count == 1)
        #expect(s.appGroups.first?.id == b)
    }

    @Test func renameGroup_updatesName() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "Old")
        s.renameGroup(id, to: "New")
        #expect(s.appGroups.first?.name == "New")
    }

    @Test func renameGroup_unknownID_doesNothing() {
        let (s, _) = makeSettings()
        s.addGroup(name: "Unchanged")
        s.renameGroup(UUID(), to: "Ghost")
        #expect(s.appGroups.first?.name == "Unchanged")
    }

    // MARK: - App membership

    @Test func addApp_assignsToGroup() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "G")
        s.addApp("Slack", toGroup: id)
        #expect(s.appGroups.first?.appNames.contains("Slack") == true)
    }

    @Test func addApp_movesFromOtherGroup() {
        let (s, _) = makeSettings()
        let g1 = s.addGroup(name: "G1")
        let g2 = s.addGroup(name: "G2")
        s.addApp("Slack", toGroup: g1)
        s.addApp("Slack", toGroup: g2)

        let inG1 = s.appGroups.first(where: { $0.id == g1 })?.appNames ?? []
        let inG2 = s.appGroups.first(where: { $0.id == g2 })?.appNames ?? []

        #expect(!inG1.contains("Slack"), "Slack should have moved out of G1")
        #expect(inG2.contains("Slack"), "Slack should be in G2")
    }

    @Test func addApp_sortedAlphabetically() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "G")
        s.addApp("Zoom", toGroup: id)
        s.addApp("Slack", toGroup: id)
        s.addApp("Messages", toGroup: id)
        #expect(s.appGroups.first?.appNames == ["Messages", "Slack", "Zoom"])
    }

    @Test func removeApp_fromGroup() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "G")
        s.addApp("Slack", toGroup: id)
        s.removeApp("Slack", fromGroup: id)
        #expect(s.appGroups.first?.appNames.isEmpty == true)
    }

    @Test func group_for_appName_returnsCorrectGroup() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "G")
        s.addApp("Slack", toGroup: id)
        #expect(s.group(for: "Slack")?.id == id)
    }

    @Test func group_for_unknownApp_returnsNil() {
        let (s, _) = makeSettings()
        #expect(s.group(for: "NoSuchApp") == nil)
    }

    // MARK: - Known app names

    @Test func recordAppName_addsName() {
        let (s, _) = makeSettings()
        s.recordAppName("Mail")
        #expect(s.knownAppNames.contains("Mail"))
    }

    @Test func recordAppName_deduplicates() {
        let (s, _) = makeSettings()
        s.recordAppName("Mail")
        s.recordAppName("Mail")
        #expect(s.knownAppNames.filter { $0 == "Mail" }.count == 1)
    }

    @Test func recordAppName_sortedAlphabetically() {
        let (s, _) = makeSettings()
        s.recordAppName("Zoom")
        s.recordAppName("Apple Mail")
        s.recordAppName("Messages")
        #expect(s.knownAppNames == ["Apple Mail", "Messages", "Zoom"])
    }

    @Test func recordAppName_ignoresEmpty() {
        let (s, _) = makeSettings()
        s.recordAppName("")
        #expect(s.knownAppNames.isEmpty)
    }

    // MARK: - Presets

    @Test func saveCurrentAsPreset_appendsPreset() {
        let (s, _) = makeSettings()
        s.saveCurrentAsPreset(name: "Night")
        #expect(s.presets.count == 1)
        #expect(s.presets.first?.name == "Night")
    }

    @Test func applyPreset_restoresSettings() {
        let (s, _) = makeSettings()
        s.autoDismissSeconds = 10
        s.targetDisplayID = 99
        s.saveCurrentAsPreset(name: "Saved")

        s.autoDismissSeconds = 0
        s.targetDisplayID = 0

        let preset = s.presets.first!
        s.applyPreset(preset)

        #expect(s.autoDismissSeconds == 10)
        #expect(s.targetDisplayID == 99)
    }

    @Test func deletePreset_removesCorrectPreset() {
        let (s, _) = makeSettings()
        s.saveCurrentAsPreset(name: "A")
        s.saveCurrentAsPreset(name: "B")
        let toDelete = s.presets.first!
        s.deletePreset(toDelete)
        #expect(s.presets.count == 1)
        #expect(s.presets.first?.name == "B")
    }
}
