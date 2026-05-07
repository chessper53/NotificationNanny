import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let isEnabled      = "isEnabled"
        static let placements     = "placementsByDisplayID"
        static let autoDismiss    = "autoDismissSeconds"
        static let knownApps      = "knownApps"
        // "appPlacements2" avoids collision with the old NotificationPosition-keyed store.
        static let appPlacements  = "appPlacements2"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// Seconds before a banner is automatically hidden. 0 = never.
    @Published var autoDismissSeconds: Double {
        didSet { defaults.set(autoDismissSeconds, forKey: Key.autoDismiss) }
    }

    /// Ordered list of app names shown in the per-app section.
    @Published private(set) var knownApps: [String] {
        didSet { defaults.set(knownApps, forKey: Key.knownApps) }
    }

    /// Per-app placement overrides (position + offsets), keyed by app name.
    @Published private var appPlacements: [String: ScreenPlacement] {
        didSet { saveAppPlacements() }
    }

    /// Keyed by `CGDirectDisplayID` rendered as a decimal string.
    @Published private var placements: [String: ScreenPlacement] {
        didSet { savePlacements() }
    }

    init() {
        self.isEnabled          = (defaults.object(forKey: Key.isEnabled) as? Bool) ?? true
        self.autoDismissSeconds = defaults.double(forKey: Key.autoDismiss)
        self.knownApps          = defaults.stringArray(forKey: Key.knownApps) ?? []

        if let data = defaults.data(forKey: Key.appPlacements),
           let decoded = try? JSONDecoder().decode([String: ScreenPlacement].self, from: data) {
            self.appPlacements = decoded
        } else {
            self.appPlacements = [:]
        }

        if let data = defaults.data(forKey: Key.placements),
           let decoded = try? JSONDecoder().decode([String: ScreenPlacement].self, from: data) {
            self.placements = decoded
        } else {
            self.placements = [:]
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

    // MARK: - Per-app placement

    func appPlacement(for appName: String) -> ScreenPlacement? {
        appPlacements[appName]
    }

    func setAppPlacement(_ placement: ScreenPlacement, for appName: String) {
        appPlacements[appName] = placement
        recordApp(appName)
    }

    func removeAppPlacement(for appName: String) {
        appPlacements.removeValue(forKey: appName)
    }

    func appPlacementBinding(for appName: String) -> Binding<ScreenPlacement> {
        Binding(
            get: { [weak self] in self?.appPlacement(for: appName) ?? .default },
            set: { [weak self] in self?.setAppPlacement($0, for: appName) }
        )
    }

    func recordApp(_ name: String) {
        guard !knownApps.contains(name) else { return }
        knownApps.append(name)
    }

    func forgetApp(_ name: String) {
        knownApps.removeAll { $0 == name }
        appPlacements.removeValue(forKey: name)
    }

    // MARK: - Persistence

    private func savePlacements() {
        guard let data = try? JSONEncoder().encode(placements) else { return }
        defaults.set(data, forKey: Key.placements)
    }

    private func saveAppPlacements() {
        guard let data = try? JSONEncoder().encode(appPlacements) else { return }
        defaults.set(data, forKey: Key.appPlacements)
    }
}
