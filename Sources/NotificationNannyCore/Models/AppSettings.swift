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
        static let targetDisplayUUID    = "targetDisplayUUID"
        static let presets              = "presets"
        static let appGroups            = "appGroups"
        static let knownApps            = "knownAppNames"
        static let pauseWhileStreaming  = "pauseWhileStreaming"
        static let avoidNCPanel         = "avoidNCPanel"
        static let protectDesktopWidgets = "protectDesktopWidgets"
        static let followActiveScreen   = "followActiveScreen"
        static let pauseDuringFocus     = "pauseDuringFocus"
        static let bannerScale          = "bannerScale"
        static let holdWhileAsleep      = "holdWhileAsleep"
        static let bannerColorR         = "bannerColorR"
        static let bannerColorG         = "bannerColorG"
        static let bannerColorB         = "bannerColorB"
        static let hasBannerColor       = "hasBannerColor"
        static let bannerTextColorR     = "bannerTextColorR"
        static let bannerTextColorG     = "bannerTextColorG"
        static let bannerTextColorB     = "bannerTextColorB"
        static let hasBannerTextColor   = "hasBannerTextColor"
        static let bannerAnimation      = "bannerAnimation"
        static let hideMenuBarIcon      = "hideMenuBarIcon"
        static let snoozedUntil         = "snoozedUntil"
    }

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

    @Published package private(set) var snoozedUntil: Date? {
        didSet {
            if let d = snoozedUntil { defaults.set(d, forKey: Key.snoozedUntil) }
            else { defaults.removeObject(forKey: Key.snoozedUntil) }
        }
    }

    private var snoozeGeneration = 0

    package var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return until > Date()
    }

    package var isActive: Bool { isEnabled && !isSnoozed }

    package func snooze(minutes: Int) {
        snoozedUntil = Date().addingTimeInterval(Double(minutes) * 60)
        scheduleSnoozeExpiry()
    }

    package func endSnooze() {
        snoozeGeneration &+= 1
        if snoozedUntil != nil { snoozedUntil = nil }
    }

    private func scheduleSnoozeExpiry() {
        snoozeGeneration &+= 1
        let gen = snoozeGeneration
        guard let until = snoozedUntil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, until.timeIntervalSinceNow)) { [weak self] in
            guard let self, self.snoozeGeneration == gen else { return }
            self.endSnooze()
        }
    }

    @Published package var pauseWhileStreaming: Bool {
        didSet { defaults.set(pauseWhileStreaming, forKey: Key.pauseWhileStreaming) }
    }

    @Published package var avoidNCPanel: Bool {
        didSet { defaults.set(avoidNCPanel, forKey: Key.avoidNCPanel) }
    }

    @Published package var protectDesktopWidgets: Bool {
        didSet { defaults.set(protectDesktopWidgets, forKey: Key.protectDesktopWidgets) }
    }

    @Published package var followActiveScreen: Bool {
        didSet { defaults.set(followActiveScreen, forKey: Key.followActiveScreen) }
    }

    @Published package var pauseDuringFocus: Bool {
        didSet { defaults.set(pauseDuringFocus, forKey: Key.pauseDuringFocus) }
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

    @Published private var bannerTextColorR: Double { didSet { defaults.set(bannerTextColorR, forKey: Key.bannerTextColorR) } }
    @Published private var bannerTextColorG: Double { didSet { defaults.set(bannerTextColorG, forKey: Key.bannerTextColorG) } }
    @Published private var bannerTextColorB: Double { didSet { defaults.set(bannerTextColorB, forKey: Key.bannerTextColorB) } }
    @Published package private(set) var hasBannerTextColor: Bool { didSet { defaults.set(hasBannerTextColor, forKey: Key.hasBannerTextColor) } }

    @Published package var bannerAnimation: BannerAnimation {
        didSet { defaults.set(bannerAnimation.rawValue, forKey: Key.bannerAnimation) }
    }

    @Published package var hideMenuBarIcon: Bool {
        didSet { defaults.set(hideMenuBarIcon, forKey: Key.hideMenuBarIcon) }
    }

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

    package var bannerTint: BannerTint? {
        get { hasBannerColor ? BannerTint(r: bannerColorR, g: bannerColorG, b: bannerColorB) : nil }
        set {
            if let t = newValue {
                bannerColorR = t.r; bannerColorG = t.g; bannerColorB = t.b; hasBannerColor = true
            } else {
                bannerColorR = 0; bannerColorG = 0; bannerColorB = 0; hasBannerColor = false
            }
        }
    }

    package func clearBannerColor() { bannerTint = nil }

    package var bannerTextTint: BannerTint? {
        get {
            hasBannerTextColor
                ? BannerTint(r: bannerTextColorR, g: bannerTextColorG, b: bannerTextColorB)
                : nil
        }
        set {
            if let tint = newValue {
                bannerTextColorR = tint.r
                bannerTextColorG = tint.g
                bannerTextColorB = tint.b
                hasBannerTextColor = true
            } else {
                bannerTextColorR = 0
                bannerTextColorG = 0
                bannerTextColorB = 0
                hasBannerTextColor = false
            }
        }
    }

    package var effectiveBannerTextColor: Color? { bannerTextTint?.color }

    package func clearBannerTextColor() { bannerTextTint = nil }

    package func effectiveBannerColor(for appName: String?) -> Color {
        effectiveBannerColorImpl(groupTint: appName.flatMap { group(for: $0) }?.bannerTint)
    }

    package func effectiveBannerColor(forGroupID groupID: UUID?) -> Color {
        effectiveBannerColorImpl(groupTint: groupID.flatMap { group(by: $0) }?.bannerTint)
    }

    private func effectiveBannerColorImpl(groupTint: BannerTint?) -> Color {
        if let tint = groupTint { return tint.color.opacity(0.55) }
        if let tint = bannerTint { return tint.color.opacity(0.55) }
        return .clear
    }

    @Published package var targetDisplayID: CGDirectDisplayID {
        didSet {
            defaults.set(Int(targetDisplayID), forKey: Key.targetDisplay)
            if let key = Self.stableKey(forDisplayID: targetDisplayID) {
                defaults.set(key, forKey: Key.targetDisplayUUID)
            } else {
                defaults.removeObject(forKey: Key.targetDisplayUUID)
            }
        }
    }

    package func resolvedTargetScreen() -> NSScreen? {
        Self.resolveScreen(displayID: targetDisplayID, stableKey: defaults.string(forKey: Key.targetDisplayUUID))
    }

    package func resolvedTargetScreen(for appName: String?) -> NSScreen? {
        guard let appName, let g = group(for: appName) else { return nil }
        return Self.resolveScreen(displayID: g.targetDisplayID, stableKey: g.targetDisplayUUID)
    }

    package func resolvedTargetScreen(forGroupID groupID: UUID?) -> NSScreen? {
        guard let groupID, let g = group(by: groupID) else { return nil }
        return Self.resolveScreen(displayID: g.targetDisplayID, stableKey: g.targetDisplayUUID)
    }

    private static func stableKey(forDisplayID id: CGDirectDisplayID) -> String? {
        guard id != 0 else { return nil }
        return NSScreen.screens.first(where: { $0.displayID == id })?.stableDisplayKey
    }

    private static func resolveScreen(displayID: CGDirectDisplayID, stableKey: String?) -> NSScreen? {
        guard displayID != 0 else { return nil }
        if let stableKey, let screen = NSScreen.screens.first(where: { $0.stableDisplayKey == stableKey }) {
            return screen
        }
        return NSScreen.screens.first(where: { $0.displayID == displayID })
    }

    func setGroupTargetDisplay(_ displayID: CGDirectDisplayID, forGroupID groupID: UUID) {
        guard let i = appGroups.firstIndex(where: { $0.id == groupID }) else { return }
        var group = appGroups[i]
        group.targetDisplayID = displayID
        group.targetDisplayUUID = Self.stableKey(forDisplayID: displayID)
        appGroups[i] = group
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

    @Published private(set) var knownAppNames: [String] {
        didSet { saveKnownApps() }
    }

    package init(defaults: UserDefaults = .standard, knownAppsFileURL: URL? = nil) {
        self.defaults           = defaults
        self.knownAppsFileURL   = knownAppsFileURL ?? Self.defaultKnownAppsFileURL
        self.isEnabled             = (defaults.object(forKey: Key.isEnabled) as? Bool) ?? true
        if let d = defaults.object(forKey: Key.snoozedUntil) as? Date, d > Date() {
            self.snoozedUntil = d
        } else {
            self.snoozedUntil = nil
        }
        self.pauseWhileStreaming    = (defaults.object(forKey: Key.pauseWhileStreaming) as? Bool) ?? false
        self.avoidNCPanel          = (defaults.object(forKey: Key.avoidNCPanel) as? Bool) ?? true
        self.protectDesktopWidgets = (defaults.object(forKey: Key.protectDesktopWidgets) as? Bool) ?? true
        self.followActiveScreen    = (defaults.object(forKey: Key.followActiveScreen) as? Bool) ?? false
        self.pauseDuringFocus      = (defaults.object(forKey: Key.pauseDuringFocus) as? Bool) ?? false
        self.holdWhileAsleep       = (defaults.object(forKey: Key.holdWhileAsleep) as? Bool) ?? false
        self.autoDismissSeconds    = defaults.double(forKey: Key.autoDismiss)
        let storedScale = defaults.double(forKey: Key.bannerScale)
        self.bannerScale = storedScale == 0 ? 1.0 : storedScale
        self.bannerColorR = defaults.object(forKey: Key.bannerColorR) as? Double ?? 0.0
        self.bannerColorG = defaults.object(forKey: Key.bannerColorG) as? Double ?? 0.0
        self.bannerColorB = defaults.object(forKey: Key.bannerColorB) as? Double ?? 0.0
        self.hasBannerColor = (defaults.object(forKey: Key.hasBannerColor) as? Bool) ?? false
        self.bannerTextColorR = defaults.object(forKey: Key.bannerTextColorR) as? Double ?? 0.0
        self.bannerTextColorG = defaults.object(forKey: Key.bannerTextColorG) as? Double ?? 0.0
        self.bannerTextColorB = defaults.object(forKey: Key.bannerTextColorB) as? Double ?? 0.0
        self.hasBannerTextColor = (defaults.object(forKey: Key.hasBannerTextColor) as? Bool) ?? false
        if let raw = defaults.string(forKey: Key.bannerAnimation),
           let anim = BannerAnimation(rawValue: raw) {
            self.bannerAnimation = anim
        } else {
            self.bannerAnimation = .default
        }
        self.hideMenuBarIcon = (defaults.object(forKey: Key.hideMenuBarIcon) as? Bool) ?? false
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

        if let data = try? Data(contentsOf: self.knownAppsFileURL),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            self.knownAppNames = names
        } else if let stored = defaults.stringArray(forKey: Key.knownApps) {
            self.knownAppNames = stored
        } else {
            self.knownAppNames = []
        }

        if snoozedUntil != nil { scheduleSnoozeExpiry() }

        migrateLegacyPlacementKeys()
        backfillTargetDisplayUUID()
        backfillGroupTargetDisplayUUIDs()
    }

    func placement(for screen: NSScreen) -> ScreenPlacement {
        placements[screen.stableDisplayKey] ?? placements[String(screen.displayID)] ?? .default
    }

    func setPlacement(_ placement: ScreenPlacement, for screen: NSScreen) {
        var updated = placements
        updated[screen.stableDisplayKey] = placement
        updated.removeValue(forKey: String(screen.displayID))
        placements = updated
    }

    func placementBinding(for screen: NSScreen) -> Binding<ScreenPlacement> {
        Binding(
            get: { [weak self] in self?.placement(for: screen) ?? .default },
            set: { [weak self] in self?.setPlacement($0, for: screen) }
        )
    }

    func group(for appName: String) -> AppGroup? {
        appGroups.first { $0.appNames.contains(appName) }
    }

    func group(by id: UUID) -> AppGroup? {
        appGroups.first { $0.id == id }
    }

    package func placement(for appName: String?, screen: NSScreen) -> ScreenPlacement {
        if let appName, let g = group(for: appName) { return g.placement }
        return placement(for: screen)
    }

    package func placement(forGroupID groupID: UUID?, screen: NSScreen) -> ScreenPlacement {
        if let groupID, let g = group(by: groupID) { return g.placement }
        return placement(for: screen)
    }

    package func targetDisplay(for appName: String?) -> CGDirectDisplayID {
        if let appName, let g = group(for: appName) { return g.targetDisplayID }
        return 0
    }

    package func targetDisplay(forGroupID groupID: UUID?) -> CGDirectDisplayID {
        if let groupID, let g = group(by: groupID) { return g.targetDisplayID }
        return 0
    }

    func placementBinding(for groupID: UUID) -> Binding<ScreenPlacement> {
        Binding(
            get: { [weak self] in self?.group(by: groupID)?.placement ?? .default },
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
        appName.flatMap { group(for: $0) }?.bannerScale ?? bannerScale
    }

    package func effectiveBannerScale(forGroupID groupID: UUID?) -> Double {
        groupID.flatMap { group(by: $0) }?.bannerScale ?? bannerScale
    }

    package func effectiveBannerMode(for appName: String?) -> BannerMode? {
        appName.flatMap { group(for: $0) }?.bannerMode
    }

    package func effectiveBannerMode(forGroupID groupID: UUID?) -> BannerMode? {
        groupID.flatMap { group(by: $0) }?.bannerMode
    }

    package func effectiveBannerAnimation(for appName: String?) -> BannerAnimation {
        appName.flatMap { group(for: $0) }?.bannerAnimation ?? bannerAnimation
    }

    package func effectiveBannerAnimation(forGroupID groupID: UUID?) -> BannerAnimation {
        groupID.flatMap { group(by: $0) }?.bannerAnimation ?? bannerAnimation
    }

    package func shouldUseCustomBanner(for appName: String?) -> Bool {
        shouldUseCustomBannerImpl(
            mode: effectiveBannerMode(for: appName),
            scale: effectiveBannerScale(for: appName),
            animation: effectiveBannerAnimation(for: appName),
            resolvedGroup: appName.flatMap { group(for: $0) }
        )
    }

    package func shouldUseCustomBanner(forGroupID groupID: UUID?) -> Bool {
        shouldUseCustomBannerImpl(
            mode: effectiveBannerMode(forGroupID: groupID),
            scale: effectiveBannerScale(forGroupID: groupID),
            animation: effectiveBannerAnimation(forGroupID: groupID),
            resolvedGroup: groupID.flatMap { group(by: $0) }
        )
    }

    private func shouldUseCustomBannerImpl(mode: BannerMode?, scale: Double,
                                           animation: BannerAnimation, resolvedGroup: AppGroup?) -> Bool {
        switch mode {
        case .native: return false
        case .custom: return true
        case nil:
            if abs(scale - 1.0) > 0.001 { return true }
            if animation != .default { return true }
            if hasBannerTextColor { return true }
            return resolvedGroup?.hasBannerColor ?? hasBannerColor
        }
    }

    package func recordAppName(_ name: String) {
        guard !name.isEmpty, !knownAppNames.contains(name) else { return }
        knownAppNames.append(name)
        knownAppNames.sort()
    }

    static let currentExportSchemaVersion = 1

    struct SettingsExport: Codable {
        var schemaVersion: Int?
        var placements: [String: ScreenPlacement]
        var targetDisplayID: CGDirectDisplayID
        var autoDismissSeconds: Double
        var bannerScale: Double
        var pauseWhileStreaming: Bool
        var avoidNCPanel: Bool
        var protectDesktopWidgets: Bool?
        var followActiveScreen: Bool?
        var pauseDuringFocus: Bool?
        var appGroups: [AppGroup]
        var presets: [Preset]
    }

    func exportData() throws -> Data {
        let export = SettingsExport(
            schemaVersion: Self.currentExportSchemaVersion,
            placements: placements,
            targetDisplayID: targetDisplayID,
            autoDismissSeconds: autoDismissSeconds,
            bannerScale: bannerScale,
            pauseWhileStreaming: pauseWhileStreaming,
            avoidNCPanel: avoidNCPanel,
            protectDesktopWidgets: protectDesktopWidgets,
            followActiveScreen: followActiveScreen,
            pauseDuringFocus: pauseDuringFocus,
            appGroups: appGroups,
            presets: presets
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    func importData(_ data: Data) throws {
        let imported = try JSONDecoder().decode(SettingsExport.self, from: data)
        let version = imported.schemaVersion ?? 1
        if version > Self.currentExportSchemaVersion {
            NannyLogger.shared.log(
                "Importing backup from a newer schema (v\(version) > v\(Self.currentExportSchemaVersion)) — unknown fields ignored",
                level: .warn, tag: "Backup")
        }
        placements          = imported.placements
        targetDisplayID     = imported.targetDisplayID
        autoDismissSeconds  = imported.autoDismissSeconds
        bannerScale         = imported.bannerScale
        pauseWhileStreaming  = imported.pauseWhileStreaming
        avoidNCPanel        = imported.avoidNCPanel
        protectDesktopWidgets = imported.protectDesktopWidgets ?? true
        followActiveScreen  = imported.followActiveScreen ?? false
        pauseDuringFocus    = imported.pauseDuringFocus ?? false
        appGroups           = imported.appGroups
        presets             = imported.presets
    }

    func saveCurrentAsPreset(name: String) {
        let preset = Preset(
            name: name,
            placements: placements,
            targetDisplayID: targetDisplayID,
            autoDismissSeconds: autoDismissSeconds,
            bannerScale: bannerScale,
            bannerTint: bannerTint,
            holdWhileAsleep: holdWhileAsleep,
            pauseWhileStreaming: pauseWhileStreaming,
            appGroups: appGroups,
            bannerAnimation: bannerAnimation
        )
        presets.append(preset)
    }

    func applyPreset(_ preset: Preset) {
        placements         = preset.placements
        targetDisplayID    = preset.targetDisplayID
        autoDismissSeconds = preset.autoDismissSeconds
        bannerScale        = preset.bannerScale
        bannerTint         = preset.bannerTint
        holdWhileAsleep    = preset.holdWhileAsleep
        pauseWhileStreaming = preset.pauseWhileStreaming
        appGroups          = preset.appGroups
        bannerAnimation    = preset.bannerAnimation
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
    }

    package func resetAllSettings() {
        isEnabled          = true
        autoDismissSeconds = 0
        targetDisplayID    = 0
        placements         = [:]
        presets            = []
        appGroups          = []
        bannerScale        = 1.0
        holdWhileAsleep    = false
        bannerTint         = nil
        bannerTextTint     = nil
        bannerAnimation    = .default
        hideMenuBarIcon    = false
    }

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

    private func migrateLegacyPlacementKeys() {
        var updated = placements
        var migrated = 0
        for screen in NSScreen.screens {
            let legacyKey = String(screen.displayID)
            guard let legacy = updated[legacyKey] else { continue }
            let stableKey = screen.stableDisplayKey
            if updated[stableKey] == nil { updated[stableKey] = legacy }
            updated.removeValue(forKey: legacyKey)
            migrated += 1
        }
        guard migrated > 0 else { return }
        placements = updated
        savePlacements()
        NannyLogger.shared.log("Migrated \(migrated) placement(s) to stable per-display keys", tag: "Display")
    }

    private func backfillTargetDisplayUUID() {
        guard defaults.string(forKey: Key.targetDisplayUUID) == nil,
              let key = Self.stableKey(forDisplayID: targetDisplayID) else { return }
        defaults.set(key, forKey: Key.targetDisplayUUID)
        NannyLogger.shared.log("Backfilled stable key for forced display id=\(targetDisplayID)", tag: "Display")
    }

    private func backfillGroupTargetDisplayUUIDs() {
        var updated = appGroups
        var changed = false
        for i in updated.indices {
            guard updated[i].targetDisplayID != 0, updated[i].targetDisplayUUID == nil,
                  let key = Self.stableKey(forDisplayID: updated[i].targetDisplayID) else { continue }
            updated[i].targetDisplayUUID = key
            changed = true
        }
        guard changed else { return }
        appGroups = updated
        saveAppGroups()
        NannyLogger.shared.log("Backfilled stable key(s) for exception-group forced displays", tag: "Display")
    }
}

extension AppSettings: NotificationSettingsProviding {
    package var settingsDidChange: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }
}
