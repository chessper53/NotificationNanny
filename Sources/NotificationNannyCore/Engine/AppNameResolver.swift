@preconcurrency import ApplicationServices

@MainActor
final class AppNameResolver {
    private static let bannerSubroles: Set<String> = [
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

    private func nameFromElement(_ el: AXUIElement) -> String? {
        guard let str = el.stringAttribute("AXAttributedDescription"),
              let first = str.components(separatedBy: ", ").first else { return nil }
        let cleaned = cleanAXString(first)
        return cleaned.isEmpty ? nil : cleaned
    }
}
