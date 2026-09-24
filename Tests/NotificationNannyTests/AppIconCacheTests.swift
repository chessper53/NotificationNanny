import AppKit
import Foundation
import Testing
@testable import NotificationNannyCore

/// A custom banner only knows the app name Notification Center shows. These build
/// fake app bundles in a temporary folder and check that the name finds the icon in
/// the cases that used to fall back to the bell: a display name that differs from
/// the file name, an app in a subfolder, and an app installed after a failed lookup.
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
        // "Find My" is FindMy.app: the old `<name>.app` guess could never find it.
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

        // Installed after the first lookup failed.
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
