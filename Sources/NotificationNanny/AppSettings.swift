import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let isEnabled = "isEnabled"
        static let placements = "placementsByDisplayID"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// Keyed by `CGDirectDisplayID` rendered as a decimal string so it
    /// round-trips cleanly through JSON.
    @Published private var placements: [String: ScreenPlacement] {
        didSet { savePlacements() }
    }

    init() {
        self.isEnabled = (defaults.object(forKey: Key.isEnabled) as? Bool) ?? true

        if let data = defaults.data(forKey: Key.placements),
           let decoded = try? JSONDecoder().decode([String: ScreenPlacement].self, from: data) {
            self.placements = decoded
        } else {
            self.placements = [:]
        }
    }

    // MARK: - Per-screen access

    func placement(for screen: NSScreen) -> ScreenPlacement {
        placements[String(screen.displayID)] ?? .default
    }

    func setPlacement(_ placement: ScreenPlacement, for screen: NSScreen) {
        placements[String(screen.displayID)] = placement
    }

    /// SwiftUI binding so the popover's grid + sliders mutate the right entry.
    func placementBinding(for screen: NSScreen) -> Binding<ScreenPlacement> {
        Binding(
            get: { [weak self] in self?.placement(for: screen) ?? .default },
            set: { [weak self] in self?.setPlacement($0, for: screen) }
        )
    }

    // MARK: - Persistence

    private func savePlacements() {
        guard let data = try? JSONEncoder().encode(placements) else { return }
        defaults.set(data, forKey: Key.placements)
    }
}
