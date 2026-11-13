@preconcurrency import ApplicationServices

@MainActor
final class AppNameResolver {
    static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterBannerStack",
        "AXNotificationCenterAlert",
        "AXNotificationCenterAlertStack",
    ]

    private var cache: [CFHashCode: String] = [:]

    func appName(for window: AXUIElement) -> String? {
        let key = CFHash(window)
        if let cached = cache[key] { return cached }
        let el = findBannerElement(in: window) ?? window
        guard let name = nameFromElement(el) else { return nil }
        cache[key] = name
        return name
    }

    func invalidate(key: CFHashCode) {
        cache.removeValue(forKey: key)
    }

    func invalidateAll() {
        cache.removeAll()
    }

    func findBannerElement(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 7 else { return nil }
        if let sr = el.stringAttribute(kAXSubroleAttribute as String), Self.bannerSubroles.contains(sr) {
            return el
        }
        for child in el.children() {
            if let found = findBannerElement(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Finds all banners in a shared host, newest first from macOS 26 onward.
    func findBannerElements(in el: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 7 else { return [] }
        if let sr = el.stringAttribute(kAXSubroleAttribute as String), Self.bannerSubroles.contains(sr) {
            return [el]
        }
        return el.children().flatMap { findBannerElements(in: $0, depth: depth + 1) }
    }

    /// Extracts the app name from a single banner description, not the shared window.
    nonisolated static func appName(fromDescription description: String) -> String? {
        guard let first = description.components(separatedBy: ", ").first else { return nil }
        let cleaned = cleanAXString(first)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Use the labelled title to separate the app in macOS 27 Persistent descriptions: "App Title,
    /// Body".
    nonisolated static func appName(fromDescription description: String, title: String?) -> String? {
        let cleaned = cleanAXString(description)
        if let title, !title.isEmpty {
            // Require the full title so "Microsoft Teams Teams, Hi" resolves to Microsoft Teams.
            let padded = cleaned + ", "
            for marker in [", \(title), ", " \(title), "] {
                guard let range = padded.range(of: marker) else { continue }
                let app = cleanAXString(String(padded[..<range.lowerBound]))
                // A comma before the title means the match was in the body.
                if !app.isEmpty, !app.contains(", ") { return app }
            }
        }
        return appName(fromDescription: cleaned)
    }

    /// The app a banner element belongs to; see `appName(fromDescription:title:)`.
    static func appName(of banner: AXUIElement) -> String? {
        guard let description = banner.stringAttribute("AXAttributedDescription") else { return nil }
        return appName(fromDescription: description, title: banner.identifiedTextValues()["title"])
    }

    private func nameFromElement(_ el: AXUIElement) -> String? {
        Self.appName(of: el)
    }
}
