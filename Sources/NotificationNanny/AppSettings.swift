import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let isEnabled     = "isEnabled"
        static let placements    = "placementsByDisplayID"
        static let autoDismiss   = "autoDismissSeconds"
        static let targetDisplay = "targetDisplayID"
        static let presets       = "presets"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    @Published var autoDismissSeconds: Double {
        didSet { defaults.set(autoDismissSeconds, forKey: Key.autoDismiss) }
    }

    /// 0 = auto (follow macOS), non-zero = force to this display.
    @Published var targetDisplayID: CGDirectDisplayID {
        didSet { defaults.set(Int(targetDisplayID), forKey: Key.targetDisplay) }
    }

    @Published private var placements: [String: ScreenPlacement] {
        didSet { savePlacements() }
    }

    @Published var presets: [Preset] {
        didSet { savePresets() }
    }

    init() {
        self.isEnabled          = (defaults.object(forKey: Key.isEnabled) as? Bool) ?? true
        self.autoDismissSeconds = defaults.double(forKey: Key.autoDismiss)
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
}
