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
        static let pauseWhileStreaming  = "pauseWhileStreaming"
        static let avoidNCPanel         = "avoidNCPanel"
        static let bannerScale          = "bannerScale"
        static let holdWhileAsleep      = "holdWhileAsleep"
        static let bannerColorR         = "bannerColorR"
        static let bannerColorG         = "bannerColorG"
        static let bannerColorB         = "bannerColorB"
        static let hasBannerColor       = "hasBannerColor"
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

    @Published package var pauseWhileStreaming: Bool {
        didSet { defaults.set(pauseWhileStreaming, forKey: Key.pauseWhileStreaming) }
    }

    @Published package var avoidNCPanel: Bool {
        didSet { defaults.set(avoidNCPanel, forKey: Key.avoidNCPanel) }
    }

    @Published package var holdWhileAsleep: Bool {
        didSet { defaults.set(holdWhileAsleep, forKey: Key.holdWhileAsleep) }
    }

    @Published package var autoDismissSeconds: Double {
        didSet { defaults.set(autoDismissSeconds, forKey: Key.autoDismiss) }
    }

    @Published package var bannerScale: Double {
        didSet { defaults.set(bannerScale, forKey: Key.bannerScale) }
    }

    @Published private var bannerColorR: Double { didSet { defaults.set(bannerColorR, forKey: Key.bannerColorR) } }
    @Published private var bannerColorG: Double { didSet { defaults.set(bannerColorG, forKey: Key.bannerColorG) } }
    @Published private var bannerColorB: Double { didSet { defaults.set(bannerColorB, forKey: Key.bannerColorB) } }
    @Published package private(set) var hasBannerColor: Bool { didSet { defaults.set(hasBannerColor, forKey: Key.hasBannerColor) } }

    package var bannerColor: Color {
        get { Color(red: bannerColorR, green: bannerColorG, blue: bannerColorB) }
        set {
            let c = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
            bannerColorR = Double(c.redComponent)
            bannerColorG = Double(c.greenComponent)
            bannerColorB = Double(c.blueComponent)
            hasBannerColor = true
        }
    }

    package func clearBannerColor() {
        hasBannerColor = false
        bannerColorR = 0; bannerColorG = 0; bannerColorB = 0
    }

    package func effectiveBannerColor(for appName: String?) -> Color {
        if let appName, let g = group(for: appName), g.hasBannerColor,
           let r = g.bannerColorR, let gr = g.bannerColorG, let b = g.bannerColorB {
            return Color(red: r, green: gr, blue: b).opacity(0.55)
        }
        if hasBannerColor { return Color(red: bannerColorR, green: bannerColorG, blue: bannerColorB).opacity(0.55) }
        return .clear
    }

    package func effectiveBannerColor(forGroupID groupID: UUID?) -> Color {
        if let groupID, let g = appGroups.first(where: { $0.id == groupID }), g.hasBannerColor,
           let r = g.bannerColorR, let gr = g.bannerColorG, let b = g.bannerColorB {
            return Color(red: r, green: gr, blue: b).opacity(0.55)
        }
        if hasBannerColor { return Color(red: bannerColorR, green: bannerColorG, blue: bannerColorB).opacity(0.55) }
        return .clear
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
        self.pauseWhileStreaming    = (defaults.object(forKey: Key.pauseWhileStreaming) as? Bool) ?? false
        self.avoidNCPanel          = (defaults.object(forKey: Key.avoidNCPanel) as? Bool) ?? true
        self.holdWhileAsleep       = (defaults.object(forKey: Key.holdWhileAsleep) as? Bool) ?? false
        self.autoDismissSeconds    = defaults.double(forKey: Key.autoDismiss)
        let storedScale = defaults.double(forKey: Key.bannerScale)
        self.bannerScale = storedScale == 0 ? 1.0 : storedScale
        self.bannerColorR = defaults.object(forKey: Key.bannerColorR) as? Double ?? 0.0
        self.bannerColorG = defaults.object(forKey: Key.bannerColorG) as? Double ?? 0.0
        self.bannerColorB = defaults.object(forKey: Key.bannerColorB) as? Double ?? 0.0
        self.hasBannerColor = (defaults.object(forKey: Key.hasBannerColor) as? Bool) ?? false
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

    package func targetDisplay(for appName: String?) -> CGDirectDisplayID {
        if let appName, let g = group(for: appName) { return g.targetDisplayID }
        return 0
    }

    package func targetDisplay(forGroupID groupID: UUID?) -> CGDirectDisplayID {
        if let groupID, let g = appGroups.first(where: { $0.id == groupID }) { return g.targetDisplayID }
        return 0
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

    package func effectiveBannerScale(for appName: String?) -> Double {
        if let appName, let g = group(for: appName), let scale = g.bannerScale { return scale }
        return bannerScale
    }

    package func effectiveBannerScale(forGroupID groupID: UUID?) -> Double {
        if let groupID, let g = appGroups.first(where: { $0.id == groupID }), let scale = g.bannerScale { return scale }
        return bannerScale
    }

    package func effectiveBannerMode(for appName: String?) -> BannerMode? {
        if let appName, let g = group(for: appName) { return g.bannerMode }
        return nil
    }

    package func effectiveBannerMode(forGroupID groupID: UUID?) -> BannerMode? {
        if let groupID, let g = appGroups.first(where: { $0.id == groupID }) { return g.bannerMode }
        return nil
    }

    package func shouldUseCustomBanner(for appName: String?) -> Bool {
        switch effectiveBannerMode(for: appName) {
        case .native: return false
        case .custom: return true
        case nil:
            if abs(effectiveBannerScale(for: appName) - 1.0) > 0.001 { return true }
            if let appName, let g = group(for: appName) { return g.hasBannerColor }
            return hasBannerColor
        }
    }

    package func shouldUseCustomBanner(forGroupID groupID: UUID?) -> Bool {
        switch effectiveBannerMode(forGroupID: groupID) {
        case .native: return false
        case .custom: return true
        case nil:
            if abs(effectiveBannerScale(forGroupID: groupID) - 1.0) > 0.001 { return true }
            if let groupID, let g = appGroups.first(where: { $0.id == groupID }) { return g.hasBannerColor }
            return hasBannerColor
        }
    }

    /// Adds to the known-apps list if not already present. Safe to call repeatedly.
    package func recordAppName(_ name: String) {
        guard !name.isEmpty, !knownAppNames.contains(name) else { return }
        knownAppNames.append(name)
        knownAppNames.sort()
    }

    // MARK: - Import / Export

    struct SettingsExport: Codable {
        var placements: [String: ScreenPlacement]
        var targetDisplayID: CGDirectDisplayID
        var autoDismissSeconds: Double
        var bannerScale: Double
        var pauseWhileStreaming: Bool
        var avoidNCPanel: Bool
        var appGroups: [AppGroup]
        var presets: [Preset]
    }

    func exportData() throws -> Data {
        let export = SettingsExport(
            placements: placements,
            targetDisplayID: targetDisplayID,
            autoDismissSeconds: autoDismissSeconds,
            bannerScale: bannerScale,
            pauseWhileStreaming: pauseWhileStreaming,
            avoidNCPanel: avoidNCPanel,
            appGroups: appGroups,
            presets: presets
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    func importData(_ data: Data) throws {
        let imported = try JSONDecoder().decode(SettingsExport.self, from: data)
        placements          = imported.placements
        targetDisplayID     = imported.targetDisplayID
        autoDismissSeconds  = imported.autoDismissSeconds
        bannerScale         = imported.bannerScale
        pauseWhileStreaming  = imported.pauseWhileStreaming
        avoidNCPanel        = imported.avoidNCPanel
        appGroups           = imported.appGroups
        presets             = imported.presets
    }

    // MARK: - Presets

    func saveCurrentAsPreset(name: String) {
        let preset = Preset(
            name: name,
            placements: placements,
            targetDisplayID: targetDisplayID,
            autoDismissSeconds: autoDismissSeconds,
            bannerScale: bannerScale,
            bannerColorR: bannerColorR,
            bannerColorG: bannerColorG,
            bannerColorB: bannerColorB,
            hasBannerColor: hasBannerColor,
            holdWhileAsleep: holdWhileAsleep,
            pauseWhileStreaming: pauseWhileStreaming,
            appGroups: appGroups
        )
        presets.append(preset)
    }

    func applyPreset(_ preset: Preset) {
        placements = preset.placements
        targetDisplayID = preset.targetDisplayID
        autoDismissSeconds = preset.autoDismissSeconds
        bannerScale = preset.bannerScale
        bannerColorR = preset.bannerColorR
        bannerColorG = preset.bannerColorG
        bannerColorB = preset.bannerColorB
        hasBannerColor = preset.hasBannerColor
        holdWhileAsleep = preset.holdWhileAsleep
        pauseWhileStreaming = preset.pauseWhileStreaming
        appGroups = preset.appGroups
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
    }

    package func resetAllSettings() {
        isEnabled = true
        autoDismissSeconds = 0
        targetDisplayID = 0
        placements = [:]
        presets = []
        appGroups = []
        bannerScale = 1.0
        holdWhileAsleep = false
        bannerColorR = 0; bannerColorG = 0; bannerColorB = 0; hasBannerColor = false
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
