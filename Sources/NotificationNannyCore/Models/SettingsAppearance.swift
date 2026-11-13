import AppKit

/// Settings window appearance only; custom banners follow macOS.
package enum SettingsAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    package var id: String { rawValue }

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
