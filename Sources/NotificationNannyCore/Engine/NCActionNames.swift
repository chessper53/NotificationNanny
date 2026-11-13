import AppKit

/// Read every translation of Close and Clear All from Notification Center, whose language may
/// differ from ours.
@MainActor
enum NCActionNames {
    static let close = names(for: "Close")
    static let clearAll = names(for: "Clear All")
    static let showDetails = names(for: "Show Details")
    static let hideDetails = names(for: "Hide Details")
    /// Built in action names in every language; other actions belong to the notifying app.
    static let builtIn: Set<String> = close.union(clearAll).union(showDetails).union(hideDetails)
        .union(names(for: "Clear")).union(names(for: "Show")).union(names(for: "Options"))

    private static let notificationCenter = "com.apple.notificationcenterui"
    private static let fallbackPath = "/System/Library/CoreServices/NotificationCenter.app"

    private static func names(for key: String) -> Set<String> {
        translations(of: key, in: table)
    }

    /// All translations of `key`, including the English key itself.
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
