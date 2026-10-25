import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

/// Replaces the open Notification Center panel with NotificationNanny's own list.
///
/// The same idea as the custom banner: Notification Center keeps owning the panel and
/// stays the source of truth, we read it, hide it, draw our own, and pass actions back.
/// What makes it work, all measured on 27.0 with scripts/panel-probe.swift and
/// scripts/panel-lab:
///
/// - The panel opens inside the same fullscreen window as the banners, and that window
///   can still be moved while the panel is open. Parked off screen it stays open and its
///   rows still answer to actions.
/// - Notification Center puts the window back where it was when the panel opens, so it
///   can't be parked beforehand. Parked as soon as `AXExpanded` turns true, no frame of
///   the real panel was caught on screen.
/// - Every row is in the tree, not just those in view, so nothing needs scrolling.
/// - A row keeps its `AXIdentifier` while it exists, so actions find it by that.
/// - A click on any window of ours closes the real panel. `PanelClickRouter` takes those
///   clicks before Notification Center can see them.
///
/// Widgets are left out: they are drawn by their own processes and Accessibility
/// doesn't describe them.
@MainActor
final class NCPanelTakeover: ObservableObject {
    @Published private(set) var snapshot: NCPanelSnapshot = .empty
    private(set) var isActive = false

    /// Called when the panel opens, before ours shows.
    var onBegin: (() -> Void)?
    /// Called after the panel closes, so the repositioner can place banners again.
    var onEnd: (() -> Void)?
    /// The app's own tint from its exception group, if any. Read by the panel's view.
    var tint: (String) -> Color? = { _ in nil }
    /// Whether rows show when they arrived.
    var showTimes: () -> Bool = { false }

    private let times: NotificationTimes
    /// When the panel opened. Rows listed then came in before it; rows that appear later
    /// arrive while it is open. The list can be empty for a moment after opening, so
    /// "listed then" lasts until it has rows or briefly after.
    private var openedAt: Double = 0
    private var listedBaselineTaken = false

    private let logger: NannyLogger
    private let router = PanelClickRouter()
    private lazy var panel = CustomNCPanelController(takeover: self)

    private var ncApp: AXUIElement?
    private var window: AXUIElement?
    /// Where Notification Center put its window, given back when the panel closes.
    private var home: CGPoint?
    private var rowElements: [String: AXUIElement] = [:]
    /// Show Less and Clear of an expanded group, in that order, by group ID.
    private var groupButtons: [String: [AXUIElement]] = [:]
    /// Clear All of a section, by section ID.
    private var sectionButtons: [Int: AXUIElement] = [:]
    private var watchdog: Timer?
    private var pendingRefresh: DispatchWorkItem?

    /// NN_LAB_PANEL_FILTER=prefix (scripts/panel-lab) lists only apps whose name starts with
    /// it, so a lab run's screenshots never show the user's own notifications.
    private static let labFilter = ProcessInfo.processInfo.environment["NN_LAB_PANEL_FILTER"]

    /// y of the parked window: far above any screen arrangement.
    private static let parkedY: CGFloat = -9999

    init(logger: NannyLogger, times: NotificationTimes) {
        self.logger = logger
        self.times = times
    }

    /// When the row's notification arrived, if known and times are on.
    func arrival(of row: NCPanelRow) -> Date? {
        showTimes() ? times.arrival(of: row.id) : nil
    }

    /// Whether `window` is the one this has taken over; the repositioner leaves it alone.
    func owns(_ window: AXUIElement) -> Bool {
        guard isActive, let mine = self.window else { return false }
        return CFEqual(mine, window)
    }

    /// Looks at every Notification Center event before the repositioner does. Returns
    /// true when the event belongs to the taken-over panel and needs nothing else.
    func handle(notification: String, ncApp: AXUIElement, enabled: Bool) -> Bool {
        guard enabled else {
            if isActive { end(reason: "turned off") }
            return false
        }
        self.ncApp = ncApp
        evaluate()
        guard isActive else { return false }
        // The repositioner still forgets destroyed elements it was tracking.
        return notification != kAXUIElementDestroyedNotification as String
    }

    /// Settings changed: stop if the feature was turned off while the panel is open.
    func settingsChanged(enabled: Bool) {
        if !enabled, isActive { end(reason: "turned off") }
    }

    private func evaluate() {
        let open = isPanelOpen()
        switch (open, isActive) {
        case (true, false): begin()
        case (true, true): keepParked(); scheduleRefresh()
        case (false, true): end(reason: "closed")
        case (false, false): break
        }
    }

    /// Notification Center's own word on it. Releases without `AXExpanded` never take over.
    private func isPanelOpen() -> Bool {
        guard let ncApp else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, "AXExpanded" as CFString, &value) == .success else { return false }
        return value as? Bool ?? false
    }

    private func hostWindow() -> AXUIElement? {
        guard let ncApp else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.max { ($0.size()?.width ?? 0) < ($1.size()?.width ?? 0) }
    }

    // MARK: - Lifecycle

    private func begin() {
        guard let host = hostWindow(), let origin = host.point() else { return }
        window = host
        home = origin
        isActive = true
        openedAt = ProcessInfo.processInfo.systemUptime
        listedBaselineTaken = false
        // First, before anything else: every millisecond here is a frame of the real panel.
        park(host)
        let screen = Self.screen(atAXPoint: origin) ?? NSScreen.main ?? NSScreen.screens[0]
        onBegin?()
        refresh()
        guard router.start(for: panel.window) else {
            // Without the router the first click on our panel would close the real one.
            logger.log("Custom Notification Center needs an event tap, which macOS refused — showing the real one",
                       level: .warn, tag: "Panel")
            end(reason: "no event tap")
            return
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        showWhenFilled(on: screen, deadline: ProcessInfo.processInfo.systemUptime + 0.3)
    }

    /// `AXExpanded` can turn true a moment before the list is in the window, and an empty
    /// panel that fills a frame later reads as "No notifications" flashing by. The real
    /// panel is parked meanwhile, so waiting costs nothing visible.
    private func showWhenFilled(on screen: NSScreen, deadline: Double) {
        guard isActive else { return }
        if snapshot.isEmpty, ProcessInfo.processInfo.systemUptime < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.refresh()
                self?.showWhenFilled(on: screen, deadline: deadline)
            }
            return
        }
        panel.show(on: screen)
        logger.log("Notification Center opened — showing NotificationNanny's list (\(snapshot.rowCount) notification(s))",
                   tag: "Panel")
    }

    private func end(reason: String) {
        router.stop()
        panel.hide()
        watchdog?.invalidate()
        watchdog = nil
        pendingRefresh?.cancel()
        if let window, let home { _ = setPosition(window, home) }
        isActive = false
        window = nil
        home = nil
        rowElements = [:]
        groupButtons = [:]
        sectionButtons = [:]
        snapshot = .empty
        logger.log("Custom Notification Center closed (\(reason))", tag: "Panel")
        onEnd?()
    }

    private func park(_ host: AXUIElement) {
        guard let x = home?.x ?? host.point()?.x else { return }
        _ = setPosition(host, CGPoint(x: x, y: Self.parkedY))
    }

    /// Notification Center moves its window back when the panel opens, and may again.
    private func keepParked() {
        guard let window, let p = window.point() else { return }
        if abs(p.y - Self.parkedY) > 1 { park(window) }
    }

    @discardableResult
    private func setPosition(_ window: AXUIElement, _ point: CGPoint) -> AXError {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func screen(atAXPoint p: CGPoint) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let appKit = NSPoint(x: p.x + 1, y: primary.frame.maxY - p.y - 1)
        return NSScreen.screens.first { $0.frame.contains(appKit) }
    }

    // MARK: - Reading the list

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
    }

    private func refresh() {
        guard let window, let list = Self.findList(in: window) else {
            if snapshot != .empty { snapshot = .empty }
            return
        }
        var entries: [NCListEntry] = []
        var elements: [AXUIElement] = []
        var allIDs: Set<String> = []
        // In a lab run, a header of an app filtered out goes with its buttons.
        var skippingHeader = false
        for child in Self.visualOrder(list.children()) {
            let role = child.stringAttribute(kAXRoleAttribute as String)
            if skippingHeader, role == (kAXButtonRole as String) { continue }
            skippingHeader = false
            if let sub = child.stringAttribute(kAXSubroleAttribute as String), AppNameResolver.bannerSubroles.contains(sub) {
                guard let row = Self.readRow(child, subrole: sub) else { continue }
                allIDs.insert(row.id)
                if let only = Self.labFilter, !row.appName.hasPrefix(only) { continue }
                entries.append(.row(row))
            } else if role == "AXHeading" {
                let text = cleanAXString(child.stringAttribute("AXAttributedDescription")
                    ?? child.stringAttribute(kAXDescriptionAttribute as String) ?? "")
                if let only = Self.labFilter, !text.hasPrefix(only) {
                    skippingHeader = true
                    continue
                }
                entries.append(.heading(text))
            } else if role == (kAXButtonRole as String) {
                entries.append(.button)
            } else {
                continue
            }
            elements.append(child)
        }
        noteTimes(allIDs)
        let next = NCPanelSnapshot.build(from: entries)
        mapElements(entries: entries, elements: elements)
        if next != snapshot { snapshot = next }
    }

    private func noteTimes(_ ids: Set<String>) {
        let settled = ProcessInfo.processInfo.systemUptime - openedAt > 0.3
        if !listedBaselineTaken {
            guard !ids.isEmpty || settled else { return }
            ids.forEach { times.noteAlreadyListed($0) }
            listedBaselineTaken = true
        } else {
            ids.forEach { times.noteArrival($0) }
        }
        // The open panel lists every notification there is.
        if !ids.isEmpty { times.prune(keeping: ids) }
    }

    /// Records which element answers for which row and header button, the same way
    /// `NCPanelSnapshot.build` decides groups and sections.
    private func mapElements(entries: [NCListEntry], elements: [AXUIElement]) {
        var rows: [String: AXUIElement] = [:]
        var groups: [String: [AXUIElement]] = [:]
        var sections: [Int: AXUIElement] = [:]
        var sectionCount = 1
        var buttonsFor: (group: String?, section: Int?) = (nil, nil)
        for (i, entry) in entries.enumerated() {
            switch entry {
            case .row(let row):
                rows[row.id] = elements[i]
                buttonsFor = (nil, nil)
            case .heading(let text):
                if NCPanelSnapshot.headingOpensGroup(at: i, in: entries) {
                    buttonsFor = ("group:\(sectionCount - 1):\(text)", nil)
                } else {
                    sectionCount += 1
                    buttonsFor = (nil, sectionCount - 1)
                }
            case .button:
                if let g = buttonsFor.group { groups[g, default: []].append(elements[i]) }
                if let s = buttonsFor.section { sections[s] = elements[i] }
            }
        }
        rowElements = rows
        groupButtons = groups
        sectionButtons = sections
    }

    /// The list's children as they are drawn. The tree's order is not that: the header of
    /// a stack expanded after others came first in the list, above rows it is drawn below
    /// (measured on 27.0). Top to bottom, and a header's buttons after its heading, which
    /// sit on the same line.
    static func visualOrder(_ elements: [AXUIElement]) -> [AXUIElement] {
        let framed = elements.map { ($0, $0.point() ?? .zero) }.sorted { $0.1.y < $1.1.y }
        var lines: [[(AXUIElement, CGPoint)]] = []
        for item in framed {
            if let first = lines.last?.first, abs(item.1.y - first.1.y) < 4 {
                lines[lines.count - 1].append(item)
            } else {
                lines.append([item])
            }
        }
        return lines.flatMap { $0.sorted { $0.1.x < $1.1.x }.map(\.0) }
    }

    private static func findList(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 8 else { return nil }
        if el.identifier == "AXNotificationListItems" { return el }
        // Rows sit inside the list; nothing to find below one.
        if let sub = el.stringAttribute(kAXSubroleAttribute as String), AppNameResolver.bannerSubroles.contains(sub) {
            return nil
        }
        for child in el.children() {
            if let found = findList(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func readRow(_ el: AXUIElement, subrole: String) -> NCPanelRow? {
        guard let id = el.identifier else { return nil }
        let description = el.stringAttribute("AXAttributedDescription") ?? ""
        let appName = AppNameResolver.appName(fromDescription: description) ?? "Notification"
        let lines = el.identifiedTextValues()
        return NCPanelRow(id: id, appName: appName, title: lines["title"] ?? "", subtitle: lines["subtitle"] ?? "",
                          body: lines["body"] ?? "", isStack: subrole.hasSuffix("Stack"))
    }

    // MARK: - Actions, passed back to Notification Center

    /// What a click on the row does in Notification Center: opens the notification, or
    /// expands a collapsed stack.
    func activate(_ row: NCPanelRow) {
        guard let el = rowElements[row.id] else { return }
        if !row.isStack, let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == row.appName }) {
            app.activate()
        }
        AXUIElementPerformAction(el, kAXPressAction as CFString)
        guard !row.isStack else { scheduleRefresh(); return }
        // Opening a notification closes Notification Center's panel when you click it there;
        // parked, nothing it watches for happens, so it stays open. Close it as the clock does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isActive, self.isPanelOpen() else { return }
            if !Self.pressMenuBarClock() {
                self.logger.log("Couldn't find the menu bar clock to close Notification Center", level: .warn, tag: "Panel")
            }
        }
    }

    /// Opens or closes Notification Center's panel, as a click on the clock does. Since
    /// macOS 27 the clock lives in MenuBarAgent; it is found by hit testing the main
    /// display's menu bar and pressed only if it says it is the clock.
    @discardableResult
    static func pressMenuBarClock() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let system = AXUIElementCreateSystemWide()
        let right = Int(screen.frame.maxX)
        for x in stride(from: right - 1, through: right - 500, by: -6) {
            var el: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(x), 12, &el) == .success, let el,
                  el.identifier == "com.apple.menuextra.clock" else { continue }
            return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
        }
        return false
    }

    /// The row's ✕: Close for one notification, Clear All for a collapsed stack.
    func close(_ row: NCPanelRow) {
        guard let el = rowElements[row.id] else { return }
        let done = el.performCustomAction(namedAnyOf: row.isStack ? NCActionNames.clearAll : NCActionNames.close)
            || el.performCustomAction(namedAnyOf: NCActionNames.close.union(NCActionNames.clearAll))
        if !done { logger.log("Notification has no Close action", level: .warn, tag: "Panel") }
        scheduleRefresh()
    }

    func collapse(_ group: NCPanelSnapshot.Group) {
        guard let showLess = groupButtons[group.id]?.first else { return }
        AXUIElementPerformAction(showLess, kAXPressAction as CFString)
        scheduleRefresh()
    }

    func clear(_ group: NCPanelSnapshot.Group) {
        if group.expanded, let clear = groupButtons[group.id]?.last {
            AXUIElementPerformAction(clear, kAXPressAction as CFString)
        } else {
            for row in group.rows { close(row) }
        }
        scheduleRefresh()
    }

    func clearAll(_ section: NCPanelSnapshot.Section) {
        if let button = sectionButtons[section.id] {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        } else {
            for group in section.groups { clear(group) }
        }
        scheduleRefresh()
    }
}
