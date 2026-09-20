import AppKit

/// Caches app icon lookups by app name so `NotificationRepositioner` doesn't hit
/// `NSWorkspace`/Finder for every banner. Invalidated per-name when the running-app
/// list changes underneath a cached miss (app installed/updated after first lookup).
@MainActor
final class AppIconCache {
    /// Shared across the repositioner's hot lookup path and the Exceptions tab's app
    /// picker, so an icon resolved once (e.g. a directory scan) doesn't repeat for the
    /// same app name across unrelated call sites or view re-creations.
    static let shared = AppIconCache()

    private var cache: [String: NSImage] = [:]
    private var misses: Set<String> = []

    /// Returns the cached icon for `appName`, or resolves and caches it via `resolve`.
    /// A prior miss is retried once more (covers "app wasn't running/installed yet on
    /// first lookup") but isn't retried forever, so a genuinely icon-less app name
    /// doesn't re-scan `/Applications` on every banner.
    func icon(for appName: String, resolve: (String) -> NSImage?) -> NSImage? {
        if let cached = cache[appName] { return cached }
        guard !misses.contains(appName) else { return nil }
        guard let icon = resolve(appName) else {
            misses.insert(appName)
            return nil
        }
        cache[appName] = icon
        misses.remove(appName)
        return icon
    }

    func invalidate(_ appName: String) {
        cache.removeValue(forKey: appName)
        misses.remove(appName)
    }

    func invalidateAll() {
        cache.removeAll()
        misses.removeAll()
    }
}
