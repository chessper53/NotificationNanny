import AppKit

/// Caches icons by display name because banners expose neither icons nor bundle identifiers over
/// AX.
@MainActor
final class AppIconCache {
    /// Share cached icons between banner rendering and the app picker.
    static let shared = AppIconCache()

    private var cache: [String: NSImage] = [:]
    /// Retry misses after `missRetryInterval` to find newly installed apps without repeated disk
    /// scans.
    private var misses: [String: Date] = [:]
    private var index: InstalledAppIndex?
    private var indexBuiltAt = Date.distantPast

    private let roots: [InstalledAppIndex.Root]
    private let missRetryInterval: TimeInterval
    private let now: () -> Date
    private let runningApps: () -> [NSRunningApplication]

    init(roots: [InstalledAppIndex.Root] = InstalledAppIndex.defaultRoots,
         missRetryInterval: TimeInterval = 30,
         now: @escaping () -> Date = Date.init,
         runningApps: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications }) {
        self.roots = roots
        self.missRetryInterval = missRetryInterval
        self.now = now
        self.runningApps = runningApps
    }

    /// The icon for the app Notification Center calls `appName`, or nil when no
    /// running or installed app goes by that name.
    func icon(for appName: String) -> NSImage? {
        let key = InstalledAppIndex.key(appName)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        if let missedAt = misses[key], now().timeIntervalSince(missedAt) < missRetryInterval { return nil }

        guard let icon = resolve(key) else {
            misses[key] = now()
            return nil
        }
        cache[key] = icon
        misses.removeValue(forKey: key)
        return icon
    }

    /// Prewarm the index off the main thread to avoid delaying the first icon lookup.
    func prewarm() {
        guard index == nil else { return }
        let roots = roots
        Task.detached(priority: .utility) {
            let built = InstalledAppIndex(roots: roots)
            await MainActor.run {
                guard self.index == nil else { return }
                self.index = built
                self.indexBuiltAt = self.now()
            }
        }
    }

    func invalidate(_ appName: String) {
        let key = InstalledAppIndex.key(appName)
        cache.removeValue(forKey: key)
        misses.removeValue(forKey: key)
    }

    func invalidateAll() {
        cache.removeAll()
        misses.removeAll()
        index = nil
    }

    private func resolve(_ key: String) -> NSImage? {
        // A running app is the cheapest answer and matches its localized name exactly.
        if let app = runningApps().first(where: { app in
            app.localizedName.map(InstalledAppIndex.key) == key
                || app.bundleURL.map { InstalledAppIndex.key($0.deletingPathExtension().lastPathComponent) } == key
        }), let icon = app.icon {
            return icon
        }
        // Rebuild on an expired miss so newly installed apps become discoverable.
        if index == nil || (index?.url(for: key) == nil && now().timeIntervalSince(indexBuiltAt) >= missRetryInterval) {
            index = InstalledAppIndex(roots: roots)
            indexBuiltAt = now()
        }
        guard let url = index?.url(for: key) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Indexes installed apps by localized display name, bundle names, and file name.
struct InstalledAppIndex: Sendable {
    struct Root: Sendable {
        let url: URL
        /// Bound recursion for app folders; CoreServices agents are indexed only at the top level.
        let depth: Int
    }

    static let defaultRoots: [Root] = [
        Root(url: URL(fileURLWithPath: "/Applications"), depth: 3),
        Root(url: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"), depth: 3),
        Root(url: URL(fileURLWithPath: "/System/Applications"), depth: 1),
        Root(url: URL(fileURLWithPath: "/System/Library/CoreServices"), depth: 0),
    ]

    private var byName: [String: URL] = [:]
    private let languages: [String]

    /// Uses the supplied languages for app names, or the system languages when nil.
    init(roots: [Root], languages: [String]? = nil) {
        self.languages = languages ?? Self.systemLanguages()
        for root in roots { scan(root.url, depth: 0, maxDepth: root.depth) }
    }

    private static let nameKeys = ["CFBundleDisplayName", "CFBundleName"]

    /// Uses system languages because Notification Center does not follow this app's language
    /// setting.
    static func systemLanguages() -> [String] {
        let global = CFPreferencesCopyValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication,
                                            kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (global as? [String]) ?? Locale.preferredLanguages
    }

    /// Read the first available system translation directly; FileManager localizes only to
    /// languages this app ships.
    static func localizedNames(of app: URL, languages: [String]) -> [String] {
        guard let first = languages.first, !first.hasPrefix("en") else { return [] }
        let resources = app.appendingPathComponent("Contents/Resources")
        func names(in strings: Any?) -> [String] {
            guard let strings = strings as? [String: Any] else { return [] }
            return nameKeys.compactMap { strings[$0] as? String }
        }
        if let table = NSDictionary(contentsOf: resources.appendingPathComponent("InfoPlist.loctable")) as? [String: Any],
           let language = Bundle.preferredLocalizations(from: Array(table.keys), forPreferences: languages).first {
            let found = names(in: table[language])
            if !found.isEmpty { return found }
        }
        let lprojs = ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? [])
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
        guard !lprojs.isEmpty,
              let language = Bundle.preferredLocalizations(from: lprojs, forPreferences: languages).first
        else { return [] }
        let strings = resources.appendingPathComponent("\(language).lproj/InfoPlist.strings")
        return names(in: NSDictionary(contentsOf: strings))
    }

    func url(for key: String) -> URL? { byName[key] }

    /// Normalize case, diacritics, and invisible characters such as WhatsApp's U+200E prefix.
    static func key(_ name: String) -> String {
        cleanAXString(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private mutating func scan(_ dir: URL, depth: Int, maxDepth: Int) {
        // Include hidden entries: Safari.app is a hidden symlink into the system cryptex.
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else { return }
        for url in items where !url.lastPathComponent.hasPrefix(".") {
            if url.pathExtension == "app" {
                add(url)
            } else if depth < maxDepth, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                scan(url, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }

    private mutating func add(_ app: URL) {
        // Read Info.plist directly to avoid Bundle overhead for every installed app.
        var names = [
            app.deletingPathExtension().lastPathComponent,
            FileManager.default.displayName(atPath: app.path),
        ]
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        for k in Self.nameKeys {
            if let n = info?[k] as? String { names.append(n) }
        }
        names += Self.localizedNames(of: app, languages: languages)
        for name in names {
            var key = Self.key(name)
            if key.hasSuffix(".app") { key = String(key.dropLast(4)) }
            // First one wins, so /Applications beats a copy in a nested folder.
            if !key.isEmpty, byName[key] == nil { byName[key] = app }
        }
    }
}
