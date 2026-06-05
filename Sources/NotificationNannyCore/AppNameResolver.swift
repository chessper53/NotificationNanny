@preconcurrency import ApplicationServices

/// Resolves the sending app name from a NotificationCenterUI AX element.
/// Maintains a per-window-hash cache that is invalidated on element destruction.
@MainActor
final class AppNameResolver {
    private static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterBannerStack",
    ]

    private var cache: [CFHashCode: String] = [:]

    // MARK: - Public API

    /// Returns the app name for `window`, using the cache when possible.
    func appName(for window: AXUIElement) -> String? {
        let key = CFHash(window)
        if let cached = cache[key] { return cached }
        let el = findBannerElement(in: window) ?? window
        guard let name = nameFromElement(el) else { return nil }
        cache[key] = name
        return name
    }

    /// Removes the cache entry for the destroyed element.
    func invalidate(key: CFHashCode) {
        cache.removeValue(forKey: key)
    }

    /// Removes all cached entries (e.g. when the observer tears down).
    func invalidateAll() {
        cache.removeAll()
    }

    // MARK: - Banner element search

    /// Walks the AX tree looking for a child element whose subrole is a known banner subrole.
    func findBannerElement(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 7 else { return nil }
        var srRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &srRef) == .success,
           let sr = srRef as? String, Self.bannerSubroles.contains(sr) { return el }
        var cRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &cRef) == .success,
              let children = cRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findBannerElement(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    // MARK: - Private

    private func nameFromElement(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXAttributedDescription" as CFString, &ref) == .success,
              let val = ref, CFGetTypeID(val) == CFAttributedStringGetTypeID() else { return nil }
        let str = CFAttributedStringGetString((val as! CFAttributedString)) as String
        guard let first = str.components(separatedBy: ", ").first, !first.isEmpty else { return nil }
        // Strip directional Unicode marks (e.g. U+200E prepended by WhatsApp).
        let cleaned = first
            .unicodeScalars
            .filter { !$0.properties.isDefaultIgnorableCodePoint }
            .reduce(into: "") { $0.append(Character($1)) }
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }
}
