import SwiftUI

/// Supported language overrides; `.system` follows Foundation's normal resolution.
package enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, fr, es, de, it
    package var id: String { rawValue }

    /// Show language names in their own language so users can recognize them.
    @MainActor package var title: String {
        switch self {
        case .system: return LocalizationManager.shared.string("System Default")
        case .en:     return "English"
        case .fr:     return "Français"
        case .es:     return "Español"
        case .de:     return "Deutsch"
        case .it:     return "Italiano"
        }
    }

    package var displayName: LocalizedStringKey {
        switch self {
        case .system: return "System Default"
        case .en:     return "English"
        case .fr:     return "Français"
        case .es:     return "Español"
        case .de:     return "Deutsch"
        case .it:     return "Italiano"
        }
    }
}

/// Publishes language changes and resolves strings from the selected bundle without relaunching.
@MainActor
package final class LocalizationManager: ObservableObject {
    package static let shared = LocalizationManager()

    /// Also set AppleLanguages so native dialogs and future launches use the selected language.
    private static let defaultsKey = "AppleLanguages"

    @Published package private(set) var language: AppLanguage
    private var bundle: Bundle

    private init() {
        let saved = Self.savedLanguage()
        language = saved
        bundle = Self.resolveBundle(for: saved)
    }

    package func setLanguage(_ lang: AppLanguage) {
        guard lang != language else { return }
        language = lang
        bundle = Self.resolveBundle(for: lang)
        if lang == .system {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.set([lang.rawValue], forKey: Self.defaultsKey)
        }
    }

    /// The locale dates and times are written in: the chosen language, or the system's.
    package var locale: Locale {
        language == .system ? .current : Locale(identifier: language.rawValue)
    }

    /// Resolve from the selected bundle, returning the key when missing.
    package func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func savedLanguage() -> AppLanguage {
        guard let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [String],
              let code = saved.first?.split(separator: "-").first.map(String.init),
              let match = AppLanguage(rawValue: code) else {
            return .system
        }
        return match
    }

    private static func resolveBundle(for language: AppLanguage) -> Bundle {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

/// Text that observes the active localization bundle for immediate language changes.
package struct LocalizedText: View {
    @ObservedObject private var loc = LocalizationManager.shared
    private let key: String

    package init(_ key: String) { self.key = key }

    package var body: some View {
        Text(loc.string(key))
    }
}

/// Localized text with Markdown emphasis.
package struct LocalizedMarkdownText: View {
    @ObservedObject private var loc = LocalizationManager.shared
    private let key: String

    package init(_ key: String) { self.key = key }

    package var body: some View {
        if let attributed = try? AttributedString(markdown: loc.string(key)) {
            Text(attributed)
        } else {
            Text(loc.string(key))
        }
    }
}
