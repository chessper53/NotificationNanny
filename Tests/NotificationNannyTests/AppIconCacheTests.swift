import AppKit
import Foundation
import Testing
@testable import NotificationNannyCore

/// Use fake installed apps so icon lookup tests do not depend on this Mac's applications.
@Suite("AppIconCache")
@MainActor
struct AppIconCacheTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIconCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Writes `<folder>/<file>.app` with an Info.plist carrying `displayName`, if given.
    @discardableResult
    func makeApp(_ file: String, in folder: String = "", displayName: String? = nil) throws -> URL {
        let app = root.appendingPathComponent(folder).appendingPathComponent("\(file).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: String] = ["CFBundleName": file, "CFBundlePackageType": "APPL"]
        if let displayName { info["CFBundleDisplayName"] = displayName }
        (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        return app
    }

    func cache(depth: Int = 3, retry: TimeInterval = 30, now: @escaping () -> Date = Date.init) -> AppIconCache {
        AppIconCache(roots: [.init(url: root, depth: depth)], missRetryInterval: retry,
                     now: now, runningApps: { [] })
    }

    @Test func findsAppByFileName() throws {
        try makeApp("Probe App One")
        #expect(cache().icon(for: "Probe App One") != nil)
    }

    @Test func findsAppByDisplayNameThatDiffersFromFileName() throws {
        // Display name differs from the bundle file name.
        try makeApp("ProbeFindMy", displayName: "Probe Find My")
        #expect(cache().icon(for: "Probe Find My") != nil)
    }

    @Test func findsAppInSubfolder() throws {
        try makeApp("Probe Nested", in: "Vendor/Suite")
        #expect(cache().icon(for: "Probe Nested") != nil)
    }

    @Test func doesNotDescendPastDepth() throws {
        try makeApp("Probe Deep", in: "a/b")
        #expect(cache(depth: 1).icon(for: "Probe Deep") == nil)
        #expect(cache(depth: 2).icon(for: "Probe Deep") != nil)
    }

    @Test func ignoresCaseAndInvisibleMarks() throws {
        // WhatsApp puts U+200E in front of its name in accessibility strings.
        try makeApp("Probe Chat")
        #expect(cache().icon(for: "\u{200E}probe chat") != nil)
    }

    @Test func unknownNameIsNil() {
        #expect(cache().icon(for: "No Such Probe App") == nil)
        #expect(cache().icon(for: "") == nil)
    }

    @Test func missIsRetriedOnlyAfterInterval() throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let c = cache(retry: 30, now: { clock })
        #expect(c.icon(for: "Probe Late") == nil)

        try makeApp("Probe Late")
        clock += 10
        #expect(c.icon(for: "Probe Late") == nil, "a fresh miss is not retried straight away")
        clock += 25
        #expect(c.icon(for: "Probe Late") != nil, "once the interval passes the index is rebuilt")
    }

    @Test func resolvedIconIsCached() throws {
        let app = try makeApp("Probe Cached")
        let c = cache()
        let first = c.icon(for: "Probe Cached")
        try FileManager.default.removeItem(at: app)
        #expect(first != nil)
        #expect(c.icon(for: "Probe Cached") === first)
    }

    @Test func keyFoldsCaseDiacriticsAndMarks() {
        #expect(InstalledAppIndex.key("\u{200E}Café ") == InstalledAppIndex.key("cafe"))
    }
}

/// Notification Center uses system translations even for languages NotificationNanny does not ship.
@Suite("InstalledAppIndex localized names")
struct InstalledAppIndexLocalizedNameTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalizedNameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeApp(_ file: String) throws -> URL {
        let app = root.appendingPathComponent("\(file).app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        (["CFBundleName": file, "CFBundlePackageType": "APPL"] as NSDictionary)
            .write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        return app
    }

    func writeStrings(_ strings: [String: String], language: String, in app: URL) throws {
        let lproj = app.appendingPathComponent("Contents/Resources/\(language).lproj")
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        (strings as NSDictionary).write(to: lproj.appendingPathComponent("InfoPlist.strings"), atomically: true)
    }

    @Test func findsAppByNameInItsLproj() throws {
        let app = try makeApp("ProbeTalk")
        try writeStrings(["CFBundleDisplayName": "프로브톡"], language: "ko", in: app)
        try writeStrings(["CFBundleDisplayName": "ProbeTalk FR"], language: "fr", in: app)
        let index = InstalledAppIndex(roots: [.init(url: root, depth: 0)], languages: ["ko-KR", "en-US"])
        #expect(index.url(for: InstalledAppIndex.key("프로브톡"))?.lastPathComponent == "ProbeTalk.app")
        #expect(index.url(for: InstalledAppIndex.key("ProbeTalk FR")) == nil, "only the user's language")
        #expect(index.url(for: InstalledAppIndex.key("ProbeTalk")) != nil, "the English name still works")
    }

    @Test func findsSystemAppByNameInItsLoctable() throws {
        let app = try makeApp("Probe Editor")
        let table: [String: [String: String]] = [
            "ko": ["CFBundleDisplayName": "프로브 편집기"],
            "de": ["CFBundleDisplayName": "Probe-Editor"],
        ]
        (table as NSDictionary).write(to: app.appendingPathComponent("Contents/Resources/InfoPlist.loctable"),
                                      atomically: true)
        let index = InstalledAppIndex(roots: [.init(url: root, depth: 0)], languages: ["ko"])
        #expect(index.url(for: InstalledAppIndex.key("프로브 편집기")) != nil)
        #expect(index.url(for: InstalledAppIndex.key("Probe-Editor")) == nil)
    }

    @Test func englishSystemReadsNoTranslations() throws {
        let app = try makeApp("ProbeEnglish")
        try writeStrings(["CFBundleDisplayName": "Probe Anglais"], language: "fr", in: app)
        #expect(InstalledAppIndex.localizedNames(of: app, languages: ["en-GB", "fr"]).isEmpty)
    }
}

/// macOS 27 Persistent descriptions omit the comma between app name and title.
@Suite("App name from a banner's description")
struct AppNameFromDescriptionTests {
    @Test func usualBanner() {
        #expect(AppNameResolver.appName(fromDescription: "Mail, Hello, How are you", title: "Hello") == "Mail")
    }

    @Test func persistentBannerWithoutCommaAfterApp() {
        #expect(AppNameResolver.appName(fromDescription: "스크립트 편집기 Claude 1, body", title: "Claude 1")
                == "스크립트 편집기")
    }

    @Test func titleThatIsPartOfTheAppName() {
        #expect(AppNameResolver.appName(fromDescription: "Microsoft Teams Teams, Hi", title: "Teams")
                == "Microsoft Teams")
    }

    @Test func persistentBannerWithoutBody() {
        #expect(AppNameResolver.appName(fromDescription: "Script Editor Done", title: "Done") == "Script Editor")
    }

    @Test func titleWithACommaInIt() {
        #expect(AppNameResolver.appName(fromDescription: "Calendar Lunch, Bob, at noon", title: "Lunch, Bob")
                == "Calendar")
    }

    @Test func titleOnlyInTheBodyFallsBackToFirstPart() {
        #expect(AppNameResolver.appName(fromDescription: "Slack, Ping, Ping me", title: "me") == "Slack")
    }

    @Test func noTitleFallsBackToFirstPart() {
        #expect(AppNameResolver.appName(fromDescription: "Slack, Ping", title: nil) == "Slack")
    }
}
