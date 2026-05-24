import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
package final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    private enum Key {
        static let isEnabled            = "isEnabled"
        static let placements           = "placementsByDisplayID"
        static let autoDismiss          = "autoDismissSeconds"
        static let targetDisplay        = "targetDisplayID"
        static let presets              = "presets"
        static let appGroups            = "appGroups"
        static let knownApps            = "knownAppNames"
    }

    /// ~/Library/Application Support/NotificationNanny/known_apps.json
    /// Survives reinstalls and UserDefaults resets.
    private static let defaultKnownAppsFileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("NotificationNanny", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("known_apps.json")
    }()

    private let knownAppsFileURL: URL

    @Published package var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    @Published package var autoDismissSeconds: Double {
        didSet { defaults.set(autoDismissSeconds, forKey: Key.autoDismiss) }
    }

    /// 0 = auto (follow macOS), non-zero = force to this display.
    @Published package var targetDisplayID: CGDirectDisplayID {
        didSet { defaults.set(Int(targetDisplayID), forKey: Key.targetDisplay) }
    }

    @Published private var placements: [String: ScreenPlacement] {
        didSet { savePlacements() }
    }

    @Published var presets: [Preset] {
        didSet { savePresets() }
    }

    @Published var appGroups: [AppGroup] {
        didSet { saveAppGroups() }
    }

    /// Sorted unique list of app names that have sent at least one notification.
    @Published private(set) var knownAppNames: [String] {
        didSet { saveKnownApps() }
    }

    package init(defaults: UserDefaults = .standard, knownAppsFileURL: URL? = nil) {
        self.defaults           = defaults
        self.knownAppsFileURL   = knownAppsFileURL ?? Self.defaultKnownAppsFileURL
        self.isEnabled             = (defaults.object(forKey: Key.isEnabled) as? Bool) ?? true
        self.autoDismissSeconds    = defaults.double(forKey: Key.autoDismiss)
        self.targetDisplayID    = CGDirectDisplayID(max(0, defaults.integer(forKey: Key.targetDisplay)))

        if let data = defaults.data(forKey: Key.placements),
           let decoded = try? JSONDecoder().decode([String: ScreenPlacement].self, from: data) {
            self.placements = decoded
        } else {
            self.placements = [:]
        }

        if let data = defaults.data(forKey: Key.presets),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            self.presets = decoded
        } else {
            self.presets = []
        }

        if let data = defaults.data(forKey: Key.appGroups),
           let decoded = try? JSONDecoder().decode([AppGroup].self, from: data) {
            self.appGroups = decoded
        } else {
            self.appGroups = []
        }

        // Load known app names from file (survives reinstalls), fall back to UserDefaults.
        if let data = try? Data(contentsOf: self.knownAppsFileURL),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            self.knownAppNames = names
        } else if let stored = defaults.stringArray(forKey: Key.knownApps) {
            self.knownAppNames = stored
        } else {
            self.knownAppNames = []
        }
    }

    // MARK: - Per-screen placement

    func placement(for screen: NSScreen) -> ScreenPlacement {
        placements[String(screen.displayID)] ?? .default
    }

    func setPlacement(_ placement: ScreenPlacement, for screen: NSScreen) {
        placements[String(screen.displayID)] = placement
    }

    func placementBinding(for screen: NSScreen) -> Binding<ScreenPlacement> {
        Binding(
            get: { [weak self] in self?.placement(for: screen) ?? .default },
            set: { [weak self] in self?.setPlacement($0, for: screen) }
        )
    }

    // MARK: - App groups

    func group(for appName: String) -> AppGroup? {
        appGroups.first { $0.appNames.contains(appName) }
    }

    /// Returns the group placement if the app has a rule, else the per-screen default.
    package func placement(for appName: String?, screen: NSScreen) -> ScreenPlacement {
        if let appName, let g = group(for: appName) { return g.placement }
        return placement(for: screen)
    }

    package func placement(forGroupID groupID: UUID?, screen: NSScreen) -> ScreenPlacement {
        if let groupID, let g = appGroups.first(where: { $0.id == groupID }) { return g.placement }
        return placement(for: screen)
    }

    func placementBinding(for groupID: UUID) -> Binding<ScreenPlacement> {
        Binding(
            get: { [weak self] in
                self?.appGroups.first(where: { $0.id == groupID })?.placement ?? .default
            },
            set: { [weak self] newVal in
                guard let self, let i = self.appGroups.firstIndex(where: { $0.id == groupID }) else { return }
                self.appGroups[i].placement = newVal
            }
        )
    }

    @discardableResult
    func addGroup(name: String) -> UUID {
        let g = AppGroup(name: name)
        appGroups.append(g)
        return g.id
    }

    func deleteGroup(_ id: UUID) {
        appGroups.removeAll { $0.id == id }
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let i = appGroups.firstIndex(where: { $0.id == id }) else { return }
        appGroups[i].name = name
    }

    /// Assigns `appName` to `groupID`, removing it from any other group first.
    func addApp(_ appName: String, toGroup groupID: UUID) {
        for i in appGroups.indices { appGroups[i].appNames.removeAll { $0 == appName } }
        guard let i = appGroups.firstIndex(where: { $0.id == groupID }) else { return }
        appGroups[i].appNames.append(appName)
        appGroups[i].appNames.sort()
    }

    func removeApp(_ appName: String, fromGroup groupID: UUID) {
        guard let i = appGroups.firstIndex(where: { $0.id == groupID }) else { return }
        appGroups[i].appNames.removeAll { $0 == appName }
    }

    /// Adds to the known-apps list if not already present. Safe to call repeatedly.
    package func recordAppName(_ name: String) {
        guard !name.isEmpty, !knownAppNames.contains(name) else { return }
        knownAppNames.append(name)
        knownAppNames.sort()
    }

    // MARK: - Presets

    func saveCurrentAsPreset(name: String) {
        let preset = Preset(name: name, placements: placements,
                            targetDisplayID: targetDisplayID, autoDismissSeconds: autoDismissSeconds)
        presets.append(preset)
    }

    func applyPreset(_ preset: Preset) {
        placements = preset.placements
        targetDisplayID = preset.targetDisplayID
        autoDismissSeconds = preset.autoDismissSeconds
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
    }

    // MARK: - Persistence

    private func savePlacements() {
        if let data = try? JSONEncoder().encode(placements) { defaults.set(data, forKey: Key.placements) }
    }

    private func savePresets() {
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: Key.presets) }
    }

    private func saveAppGroups() {
        if let data = try? JSONEncoder().encode(appGroups) { defaults.set(data, forKey: Key.appGroups) }
    }

    private func saveKnownApps() {
        defaults.set(knownAppNames, forKey: Key.knownApps)
        if let data = try? JSONEncoder().encode(knownAppNames) {
            try? data.write(to: self.knownAppsFileURL, options: .atomic)
        }
    }
}

extension AppSettings: NotificationSettingsProviding {
    package var settingsDidChange: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }
}
