import AppKit

/// Resolves and caches app icons by the app name Notification Center shows, so
/// `NotificationRepositioner` doesn't hit `NSWorkspace` or the disk for every banner.
///
/// The name is all there is to go on: a banner exposes no bundle identifier and no
/// image over Accessibility. It is the app's display name, which often differs from
/// its file name ("Find My" is FindMy.app, "Minecraft Launcher" is Minecraft.app) and
/// the app need not be running or sit at the top of /Applications. Guessing
/// `<name>.app` in four folders missed about one installed app in eight, and every
/// miss is a custom banner drawn with a bell instead of the app's icon.
@MainActor
final class AppIconCache {
    /// Shared across the repositioner's hot lookup path and the Exceptions tab's app
    /// picker, so an icon resolved once isn't resolved again for the same name.
    static let shared = AppIconCache()

    private var cache: [String: NSImage] = [:]
    /// When each name last failed to resolve. A miss is retried once this is older
    /// than `missRetryInterval`, which covers an app installed after launch without
    /// rescanning the disk on every banner from an app that has no icon to find.
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

    /// Builds the installed app index off the main thread, so the first custom
    /// banner from an app that isn't running doesn't wait on a disk scan.
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
        // The index is built once and rebuilt at most every `missRetryInterval`, and
        // only when it could not answer, so a newly installed app is found without
        // rescanning for every notification.
        if index == nil || (index?.url(for: key) == nil && now().timeIntervalSince(indexBuiltAt) >= missRetryInterval) {
            index = InstalledAppIndex(roots: roots)
            indexBuiltAt = now()
        }
        guard let url = index?.url(for: key) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Installed apps keyed by every name Notification Center might show for them: the
/// localized display name, `CFBundleDisplayName`, `CFBundleName`, and the file name.
struct InstalledAppIndex: Sendable {
    struct Root: Sendable {
        let url: URL
        /// How many folders down to look. Apps nest one or two deep in /Applications
        /// (Utilities, Setapp, Chrome web apps, vendor folders); CoreServices only has
        /// agents worth finding at the top, and over a thousand folders below that.
        let depth: Int
    }

    static let defaultRoots: [Root] = [
        Root(url: URL(fileURLWithPath: "/Applications"), depth: 3),
        Root(url: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"), depth: 3),
        Root(url: URL(fileURLWithPath: "/System/Applications"), depth: 1),
        Root(url: URL(fileURLWithPath: "/System/Library/CoreServices"), depth: 0),
    ]

    private var byName: [String: URL] = [:]

    init(roots: [Root]) {
        for root in roots { scan(root.url, depth: 0, maxDepth: root.depth) }
    }

    func url(for key: String) -> URL? { byName[key] }

    /// Case, diacritic and invisible character insensitive, so "WhatsApp" with the
    /// U+200E that WhatsApp puts in front of its name still matches.
    static func key(_ name: String) -> String {
        cleanAXString(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private mutating func scan(_ dir: URL, depth: Int, maxDepth: Int) {
        // Not .skipsHiddenFiles: /Applications/Safari.app is a symlink into the
        // system cryptex with the hidden flag set, and would be skipped with it.
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
        // displayName is the localized name Launch Services shows, which is what
        // Notification Center shows. Reading Info.plist directly rather than through
        // Bundle is about six times faster, and this runs for every installed app.
        var names = [
            app.deletingPathExtension().lastPathComponent,
            FileManager.default.displayName(atPath: app.path),
        ]
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        for k in ["CFBundleDisplayName", "CFBundleName"] {
            if let n = info?[k] as? String { names.append(n) }
        }
        for name in names {
            var key = Self.key(name)
            if key.hasSuffix(".app") { key = String(key.dropLast(4)) }
            // First one wins, so /Applications beats a copy in a nested folder.
            if !key.isEmpty, byName[key] == nil { byName[key] = app }
        }
    }
}
