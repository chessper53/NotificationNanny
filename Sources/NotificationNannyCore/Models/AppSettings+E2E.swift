import Foundation

extension AppSettings {
    /// Only the opt-in live test runner uses this store. Normal launches keep their
    /// usual preferences; malformed test configuration must fail before AX binds.
    package static func forAppLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppSettings {
        guard let path = environment["NN_E2E_DIRECTORY"] else { return AppSettings() }
        guard environment["NN_LAB"] == "1" else { throw E2EConfigurationError.labModeRequired }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard UUID(uuidString: directory.lastPathComponent) != nil else {
            throw E2EConfigurationError.invalidDirectory
        }
        let data = try Data(contentsOf: directory.appendingPathComponent("settings.plist"))
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw E2EConfigurationError.invalidSettings
        }
        let suite = "com.notificationnanny.e2e.\(directory.lastPathComponent)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw E2EConfigurationError.invalidSettings }
        defaults.setPersistentDomain(values, forName: suite)
        return AppSettings(defaults: defaults, knownAppsFileURL: directory.appendingPathComponent("known_apps.json"))
    }

    enum E2EConfigurationError: Error {
        case labModeRequired, invalidDirectory, invalidSettings
    }
}
