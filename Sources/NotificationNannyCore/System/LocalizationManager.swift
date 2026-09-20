import SwiftUI

/// The language override this app understands, on top of whatever macOS itself provides.
/// `.system` means "no override" — follow the OS/per-app language exactly as Foundation
/// would resolve it on its own.
package enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, fr, es, de, it
    package var id: String { rawValue }

    /// Language names are shown in their own language, not translated — the standard
    /// convention for language pickers (a French speaker still recognizes "Français").
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

/// Drives hot-reloadable localization. UI text looks its string up through this manager's
/// `string(_:)` instead of relying on SwiftUI's automatic `Text(LocalizedStringKey)` →
/// `Bundle.main` resolution — which is fixed for the process's lifetime and can't hot-swap.
/// Changing `language` publishes immediately, so every `LocalizedText` (and anything else
/// reading `.shared`) re-renders in the new language without a relaunch.
///
/// AppKit call sites (the right-click menu) rebuild fresh on every open, so querying
/// `string(_:)` there picks up the current language automatically without any observation
/// plumbing at all.
@MainActor
package final class LocalizationManager: ObservableObject {
    package static let shared = LocalizationManager()

    /// Reuses Apple's own `AppleLanguages` defaults key so a relaunch (or any native,
    /// OS-rendered chrome we don't control, like Save/Open panel buttons) also starts in the
    /// right language — this manager's live hot-reload is additive on top of that, not a
    /// replacement for it.
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

    /// Looks up `key` in the active language's `Localizable.strings`, falling back to the
    /// key itself if not found — matching `NSLocalizedString`'s own missing-key behavior.
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

/// Text that looks its string up through `LocalizationManager` instead of the automatic
/// `Bundle.main` resolution `Text(LocalizedStringKey)` uses, so it hot-reloads when the user
/// picks a different language instead of needing a relaunch.
package struct LocalizedText: View {
    @ObservedObject private var loc = LocalizationManager.shared
    private let key: String

    package init(_ key: String) { self.key = key }

    package var body: some View {
        Text(loc.string(key))
    }
}

/// Like `LocalizedText`, but parses simple Markdown in the resolved string (bold/italic) —
/// for the handful of strings that use `**...**` emphasis.
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
