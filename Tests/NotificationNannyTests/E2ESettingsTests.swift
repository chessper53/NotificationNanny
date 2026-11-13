import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("E2E settings isolation") @MainActor
struct E2ESettingsTests {
    @Test func labLaunchUsesSeparatePreferencesAndKnownApps() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "com.notificationnanny.e2e.\(directory.lastPathComponent)"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let before = UserDefaults.standard.object(forKey: "bannerScale") as? Double
        let values: [String: Any] = ["bannerScale": 1.25, "isEnabled": true]
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("settings.plist"))
        let settings = try AppSettings.forAppLaunch(environment: ["NN_LAB": "1", "NN_E2E_DIRECTORY": directory.path])
        #expect(settings.bannerScale == 1.25)
        settings.bannerScale = 1.5
        settings.recordAppName("E2E fixture")
        #expect(UserDefaults(suiteName: suite)?.double(forKey: "bannerScale") == 1.5)
        #expect(UserDefaults.standard.object(forKey: "bannerScale") as? Double == before)
        let names = try JSONDecoder().decode([String].self, from: Data(contentsOf: directory.appendingPathComponent("known_apps.json")))
        #expect(names == ["E2E fixture"])
    }

    @Test func testDirectoryRequiresExplicitLabMode() {
        #expect(throws: AppSettings.E2EConfigurationError.self) {
            try AppSettings.forAppLaunch(environment: ["NN_E2E_DIRECTORY": "/tmp/\(UUID().uuidString)"])
        }
    }

    @Test func invalidTestDirectoryDoesNotFallBackToUserSettings() {
        #expect(throws: AppSettings.E2EConfigurationError.self) {
            try AppSettings.forAppLaunch(environment: ["NN_LAB": "1", "NN_E2E_DIRECTORY": "/tmp/not-a-test-run"])
        }
    }

    @Test func missingConfigurationDoesNotFallBackToUserSettings() {
        #expect(throws: (any Error).self) {
            try AppSettings.forAppLaunch(environment: ["NN_LAB": "1", "NN_E2E_DIRECTORY": "/tmp/\(UUID().uuidString)"])
        }
    }
}
