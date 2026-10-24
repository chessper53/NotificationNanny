import AppKit

/// The names Notification Center gives a banner's Close and Clear All actions. macOS
/// translates them (French reports Fermer and Tout effacer), so they are read from
/// Notification Center's own strings, in every language it ships: it can run in another
/// language than ours, and a name in any of them is still the same button.
@MainActor
enum NCActionNames {
    static let close = names(for: "Close")
    static let clearAll = names(for: "Clear All")

    private static let notificationCenter = "com.apple.notificationcenterui"
    private static let fallbackPath = "/System/Library/CoreServices/NotificationCenter.app"

    private static func names(for key: String) -> Set<String> {
        translations(of: key, in: table)
    }

    /// Every translation of `key` in a loctable, which maps each language to its strings.
    /// The key itself, the English name, is always in.
    nonisolated static func translations(of key: String, in table: [String: Any]) -> Set<String> {
        var names: Set<String> = [key]
        for case let strings as [String: Any] in table.values {
            if let name = strings[key] as? String, !name.isEmpty { names.insert(name) }
        }
        return names
    }

    /// Notification Center's Localizable.loctable, or empty if it can't be read.
    private static let table: [String: Any] = {
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notificationCenter)
            ?? URL(fileURLWithPath: fallbackPath)
        let url = app.appendingPathComponent("Contents/Resources/Localizable.loctable")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let table = plist as? [String: Any] else {
            NannyLogger.shared.log("Couldn't read Notification Center's strings, closing banners only by their English names",
                                   level: .warn, tag: "Banner")
            return [:]
        }
        return table
    }()
}
