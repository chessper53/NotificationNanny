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

    /// Every banner in the window, not just the first. Since macOS 26 they all
    /// share one host window, so banners that are up together are siblings in
    /// the same tree, newest first.
    func findBannerElements(in el: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 7 else { return [] }
        if let sr = el.stringAttribute(kAXSubroleAttribute as String), Self.bannerSubroles.contains(sr) {
            return [el]
        }
        return el.children().flatMap { findBannerElements(in: $0, depth: depth + 1) }
    }

    /// The app a single banner belongs to, from its description ("App, Title,
    /// Body"). `appName(for:)` answers for a window, which since macOS 26 holds
    /// every banner that is up.
    nonisolated static func appName(fromDescription description: String) -> String? {
        guard let first = description.components(separatedBy: ", ").first else { return nil }
        let cleaned = cleanAXString(first)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// The app, given the banner's title too. A Persistent banner on macOS 27
    /// describes itself as "App Title, Body", with no comma after the app, so the
    /// first part alone runs the app into the title. The title is a labelled line of
    /// its own, so what comes before it is the app.
    nonisolated static func appName(fromDescription description: String, title: String?) -> String? {
        let cleaned = cleanAXString(description)
        if let title, !title.isEmpty {
            // The title ends at a comma or at the end, so "Microsoft Teams Teams, Hi"
            // is Microsoft Teams and not Microsoft.
            let padded = cleaned + ", "
            for marker in [", \(title), ", " \(title), "] {
                guard let range = padded.range(of: marker) else { continue }
                let app = cleanAXString(String(padded[..<range.lowerBound]))
                // Only when the title follows the app straight away; a comma before
                // it means the title turned up later, in the body.
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
