import AppKit
import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("AppSettings") @MainActor
struct AppSettingsTests {

    private func makeSettings() -> (AppSettings, String) {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        return (AppSettings(defaults: ud, knownAppsFileURL: tempURL), name)
    }

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

    @Test func appGroup_init_defaults() {
        let g = AppGroup(name: "Work")
        #expect(!g.id.uuidString.isEmpty)
        #expect(g.name == "Work")
        #expect(g.appNames.isEmpty)
        #expect(g.placement == .default)
        #expect(g.targetDisplayID == 0)
    }

    @Test func appGroup_codable_roundTrip() throws {
        let original = AppGroup(
            id: UUID(),
            name: "Social",
            appNames: ["Slack", "Messages"],
            placement: ScreenPlacement(position: .bottomLeft, xOffset: 10, yOffset: -5),
            targetDisplayID: 42
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppGroup.self, from: data)
        #expect(decoded == original)
    }

    @Test func appGroup_codable_backwardCompat_missingTargetDisplayID() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "appNames": ["Mail"],
            "placement": {"position": "topRight", "xOffset": 0, "yOffset": 0}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppGroup.self, from: json)
        #expect(decoded.targetDisplayID == 0)
        #expect(decoded.name == "Legacy")
    }

    @Test func appGroup_equatable_differentIDs() {
        let a = AppGroup(name: "A")
        let b = AppGroup(name: "A")
        #expect(a != b, "Two groups with different UUIDs must not be equal")
    }

    @Test func bannerTextTint_defaultsToNilWithoutOverride() {
        let (settings, _) = makeSettings()
        #expect(settings.bannerTextTint == nil)
        #expect(settings.effectiveBannerTextColor == nil)
    }

    @Test func bannerTextTint_persistsAcrossSettingsInstances() {
        let (settings, suiteName) = makeSettings()
        let tint = BannerTint(r: 0.2, g: 0.4, b: 0.6)
        settings.bannerTextTint = tint

        let defaults = UserDefaults(suiteName: suiteName)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(suiteName)-restored.json")
        let restored = AppSettings(defaults: defaults, knownAppsFileURL: url)
        #expect(restored.bannerTextTint == tint)
    }

    @Test func customTextTint_activatesCustomBanner() {
        let (settings, _) = makeSettings()
        #expect(!settings.shouldUseCustomBanner(for: nil))

        settings.bannerTextTint = BannerTint(r: 1.0, g: 0.3, b: 0.2)
        #expect(settings.shouldUseCustomBanner(for: nil))

        settings.clearBannerTextColor()
        #expect(!settings.shouldUseCustomBanner(for: nil))
    }

    @Test func targetDisplay_noGroup_returnsZero() {
        let (s, _) = makeSettings()
        #expect(s.targetDisplay(for: "Slack") == 0)
        #expect(s.targetDisplay(for: nil) == 0)
    }

    @Test func targetDisplay_forApp_returnsGroupDisplay() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "Work")
        s.addApp("Slack", toGroup: id)
        guard let i = s.appGroups.firstIndex(where: { $0.id == id }) else { return }
        s.appGroups[i].targetDisplayID = 2
        #expect(s.targetDisplay(for: "Slack") == 2)
    }

    @Test func targetDisplay_forApp_notInGroup_returnsZero() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "Work")
        s.addApp("Slack", toGroup: id)
        guard let i = s.appGroups.firstIndex(where: { $0.id == id }) else { return }
        s.appGroups[i].targetDisplayID = 2
        #expect(s.targetDisplay(for: "Mail") == 0)
    }

    @Test func targetDisplay_forGroupID_returnsDisplay() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "G")
        guard let i = s.appGroups.firstIndex(where: { $0.id == id }) else { return }
        s.appGroups[i].targetDisplayID = 5
        #expect(s.targetDisplay(forGroupID: id) == 5)
    }

    @Test func targetDisplay_forGroupID_nilID_returnsZero() {
        let (s, _) = makeSettings()
        #expect(s.targetDisplay(forGroupID: nil) == 0)
    }

    @Test func targetDisplay_forGroupID_unknownID_returnsZero() {
        let (s, _) = makeSettings()
        #expect(s.targetDisplay(forGroupID: UUID()) == 0)
    }

    @Test func targetDisplay_groupDisplayZero_returnsZero() {
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "G")
        s.addApp("Slack", toGroup: id)
        #expect(s.targetDisplay(for: "Slack") == 0)
    }

    @Test func setGroupTargetDisplay_mirrorsStableKeyForConnectedScreen() {
        guard let screen = NSScreen.main else { return }
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "G")
        s.setGroupTargetDisplay(screen.displayID, forGroupID: id)
        #expect(s.appGroups.first?.targetDisplayUUID == screen.stableDisplayKey)
        #expect(s.resolvedTargetScreen(forGroupID: id) === screen)
    }

    @Test func setGroupTargetDisplay_auto_clearsStableKey() {
        guard let screen = NSScreen.main else { return }
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "G")
        s.setGroupTargetDisplay(screen.displayID, forGroupID: id)
        s.setGroupTargetDisplay(0, forGroupID: id)
        #expect(s.appGroups.first?.targetDisplayUUID == nil)
        #expect(s.resolvedTargetScreen(forGroupID: id) == nil)
    }

    @Test func resolvedTargetScreen_forApp_usesGroupOverride() {
        guard let screen = NSScreen.main else { return }
        let (s, _) = makeSettings()
        let id = s.addGroup(name: "Work")
        s.addApp("Slack", toGroup: id)
        s.setGroupTargetDisplay(screen.displayID, forGroupID: id)
        #expect(s.resolvedTargetScreen(for: "Slack") === screen)
        #expect(s.resolvedTargetScreen(for: "Mail") == nil, "app not in the group must not inherit its override")
    }

    @Test func resolvedTargetScreen_global_nilByDefault() {
        let (s, _) = makeSettings()
        #expect(s.resolvedTargetScreen() == nil)
        #expect(s.resolvedTargetScreen(for: nil) == nil)
        #expect(s.resolvedTargetScreen(forGroupID: nil) == nil)
    }

    @Test func targetDisplayID_settingToDisconnectedID_clearsStaleStableKey() {
        guard let screen = NSScreen.main else { return }
        let (s, _) = makeSettings()
        s.targetDisplayID = screen.displayID
        #expect(s.resolvedTargetScreen() === screen)

        s.targetDisplayID = 999_999
        #expect(s.resolvedTargetScreen() == nil)
    }

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
