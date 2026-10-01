import AppKit

/// Which appearance the Settings window is drawn in. Banners are not affected: a
/// custom banner always follows macOS, because it stands in for the system one.
package enum SettingsAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    package var id: String { rawValue }

    /// Localization key for the picker segment.
    package var labelKey: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// The appearance to set on the window; nil follows macOS.
    package var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}
