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
/// Widgets are pictures of the real ones, behind their own setting; see WidgetCapture.

/// What the user chose for the custom panel, in the Notification Center tab, and how
/// banners look, which the panel's rows follow.
struct NCPanelOptions: Equatable {
    var appFilter = false
    /// How the panel opens and closes.
    var animation: BannerAnimation = .default
    /// How large it is drawn, 1 being the system's size.
    var scale: CGFloat = 1
    /// Which side of the screen it opens on.
    var side: NCPanelSide = .right
    /// How much lower than the system's it starts, in points.
    var topOffset: CGFloat = 0
    /// How far across from its side's place, right being positive.
    var xOffset: CGFloat = 0
    /// Pictures of the real widgets; only acted on with Screen Recording allowed.
    var widgets = false
    /// The banners' text colour, nil for the system's.
    var textColor: Color? = nil
    /// The banners' privacy blur.
    var redact = false
}

/// A widget in Notification Center's panel, as a picture of the real one.
struct NCWidget: Identifiable {
    /// Its `AXIdentifier`, `widget-local:<app>:<kind>:<container>`.
    let id: String
    /// Where it is in Notification Center's window, in points from the window's top left.
    var frameInWindow: CGRect
    var image: NSImage?

    /// The bundle ID of the app the widget belongs to.
    var appBundleID: String? {
        let parts = id.split(separator: ":")
        return parts.count > 1 ? String(parts[1]) : nil
    }
}

@MainActor
final class NCPanelTakeover: ObservableObject {
    @Published private(set) var snapshot: NCPanelSnapshot = .empty
    @Published private(set) var options = NCPanelOptions()
    @Published private(set) var widgets: [NCWidget] = []
    /// What Notification Center shows under its list.
    @Published private(set) var footer = NCPanelFooter()
    private(set) var isActive = false

    /// The options as set now; read when the panel opens and when settings change.
    var readOptions: () -> NCPanelOptions = { NCPanelOptions() }
    /// The screen to open on instead of the one whose clock was clicked, if any: with
    /// "Don't move Notification Center" off, the screen the banners go to.
    var preferredScreen: () -> NSScreen? = { nil }

    /// Called when the panel opens, before ours shows.
    var onBegin: (() -> Void)?
    /// Called after the panel closes, so the repositioner can place banners again.
    var onEnd: (() -> Void)?
    /// The tint a banner from the app gets, clear for none. Read by the panel's view.
    var tint: (String) -> Color = { _ in .clear }

    /// A menu of Notification Center's open in our panel, nil while none is.
    @Published private(set) var menu: NCPanelMenu?

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
    /// Where the real panel's window belongs while ours is up: parked off screen, or with
    /// widgets shown, right under ours, where it is drawn and so can be captured.
    private var desiredOrigin: CGPoint?
    private var widgetElements: [String: AXUIElement] = [:]
    private let widgetCapture = WidgetCapture()
    private var widgetTimer: Timer?
    private lazy var cover = NCPanelCover()
    private let actions = NotificationActions()
    /// Mirrors a reply while one is open: the typing goes to Notification Center's field.
    private var replyTimer: Timer?
    /// The footer's Edit Widgets and Clear Notifications, while the panel shows them.
    private var editWidgetsButton: AXUIElement?
    private var clearMenuButton: AXUIElement?
    /// After the panel closes, its window goes home only once Notification Center has
    /// drawn the panel's way out, which it does wherever the window is: about 0.6 s after
    /// it says it closed (filmed on 27.0, scripts/panel-lab `native-close`). Moved back at
    /// once, the real panel was seen leaving.
    /// When the panel opened, system uptime.
    private var openedAt: Double = 0
    private var goingHome: (window: AXUIElement, home: CGPoint, work: DispatchWorkItem)?
    private static let closeAnimation: TimeInterval = 0.8

    /// NN_LAB_PANEL_FILTER=prefix (scripts/panel-lab) lists only apps whose name starts with
    /// it, so a lab run's screenshots never show the user's own notifications.
    private static let labFilter = ProcessInfo.processInfo.environment["NN_LAB_PANEL_FILTER"]

    /// y of the parked window: far above any screen arrangement.
    private static let parkedY: CGFloat = -9999

    init(logger: NannyLogger) {
        self.logger = logger
    }

    /// Whether `window` is the one this has taken over, or is still putting back; the
    /// repositioner leaves it alone.
    func owns(_ window: AXUIElement) -> Bool {
        if isActive, let mine = self.window { return CFEqual(mine, window) }
        if let going = goingHome { return CFEqual(going.window, window) }
        return false
    }

    /// Looks at every Notification Center event before the repositioner does. Returns
    /// true when the event belongs to the taken-over panel and needs nothing else.
    func handle(notification: String, ncApp: AXUIElement, enabled: Bool) -> Bool {
        guard enabled else {
            if isActive { end(reason: "turned off", stillOpen: isPanelOpen()) }
            return false
        }
        self.ncApp = ncApp
        evaluate(trigger: notification)
        guard isActive else { return false }
        // The repositioner still forgets destroyed elements it was tracking.
        return notification != kAXUIElementDestroyedNotification as String
    }

    /// Settings changed: stop if the feature was turned off while the panel is open.
    func settingsChanged(enabled: Bool) {
        if !enabled, isActive { end(reason: "turned off", stillOpen: isPanelOpen()) }
        let next = readOptions()
        guard next != options else { return }
        options = next
        // Open while its place or size is changed in Settings: it moves there at once.
        if isActive { panel.relayout() }
    }

    private func evaluate(trigger: String) {
        let open = isPanelOpen()
        switch (open, isActive) {
        case (true, false): begin()
        case (true, true): keepInPlace(); scheduleRefresh()
        case (false, true): end(reason: "closed, seen on \(trigger)")
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
        // Only the fullscreen dialog the panel opens in. Each desktop widget is a window of
        // Notification Center's too, and parking one would take it off the desktop.
        return windows.filter { $0.stringAttribute(kAXSubroleAttribute as String) == "AXSystemDialog" }
            .max { ($0.size()?.width ?? 0) < ($1.size()?.width ?? 0) }
    }

    // MARK: - Lifecycle

    private func begin() {
        guard let host = hostWindow(), let origin = host.point() else { return }
        window = host
        // Opened again before the window went home: it is still parked, and home is where
        // it was going.
        if let going = goingHome, CFEqual(going.window, host) {
            going.work.cancel()
            home = going.home
        } else {
            home = origin
        }
        goingHome?.work.cancel()
        goingHome = nil
        isActive = true
        openedAt = ProcessInfo.processInfo.systemUptime
        // First, before anything else: every millisecond here is a frame of the real panel.
        desiredOrigin = CGPoint(x: origin.x, y: Self.parkedY)
        keepInPlace()
        options = readOptions()
        let screen = preferredScreen() ?? Self.screen(atAXPoint: origin) ?? NSScreen.main ?? NSScreen.screens[0]
        onBegin?()
        refresh()
        // Clicks in Settings too: dragging the panel's place there would close it otherwise.
        router.otherWindows = { [weak self] in
            NSApp.windows.filter { $0.isVisible && $0.level == .normal && $0 !== self?.panel.window }
        }
        guard router.start(for: panel.window) else {
            // Without the router the first click on our panel would close the real one.
            logger.log("Custom Notification Center needs an event tap, which macOS refused — showing the real one",
                       level: .warn, tag: "Panel")
            end(reason: "no event tap", stillOpen: true)
            return
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate(trigger: "watchdog") }
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
        startWidgets()
    }

    private func end(reason: String, stillOpen: Bool = false) {
        router.stop()
        panel.hide(after: options.animation.outroDuration)
        stopWidgets()
        replyTimer?.invalidate()
        replyTimer = nil
        watchdog?.invalidate()
        watchdog = nil
        pendingRefresh?.cancel()
        refreshBurst.forEach { $0.cancel() }
        refreshBurst = []
        menu = nil
        if let window, let home {
            if stillOpen {
                // Turned off with the panel open: the real one is what should show now.
                _ = setPosition(window, home)
                onEnd?()
            } else {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, let going = self.goingHome else { return }
                    self.goingHome = nil
                    _ = self.setPosition(going.window, going.home)
                    self.onEnd?()
                }
                goingHome = (window, home, work)
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeAnimation, execute: work)
            }
        } else {
            onEnd?()
        }
        isActive = false
        window = nil
        home = nil
        desiredOrigin = nil
        rowElements = [:]
        groupButtons = [:]
        sectionButtons = [:]
        editWidgetsButton = nil
        clearMenuButton = nil
        snapshot = .empty
        logger.log("Custom Notification Center closed (\(reason))", tag: "Panel")
    }

    /// Sends the window home now rather than after the panel's way out, when the app quits.
    func finishClosing() {
        guard let going = goingHome else { return }
        going.work.cancel()
        goingHome = nil
        _ = setPosition(going.window, going.home)
    }

    /// Notification Center moves its window back when the panel opens, and may again.
    private func keepInPlace() {
        guard let window, let target = desiredOrigin, let p = window.point() else { return }
        if hypot(p.x - target.x, p.y - target.y) > 1 { setPosition(window, target) }
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

    /// NN_TIMING=1 (scripts/notify-lab, panel-lab) writes how long each read of the list took.
    private static let timing = ProcessInfo.processInfo.environment["NN_TIMING"] == "1"

    private func refresh() {
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            if Self.timing {
                let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                FileHandle.standardError.write(Data("[timing] panel refresh \(ms) ms, \(snapshot.rowCount) rows\n".utf8))
            }
        }
        readWidgets()
        // With no notifications there may be no list, and the footer is all there is.
        if let window { readFooter(in: window) }
        guard let window, let list = Self.findList(in: window) else {
            if snapshot != .empty { snapshot = .empty }
            return
        }
        var entries: [NCListEntry] = []
        var elements: [AXUIElement] = []
        // In a lab run, a header of an app filtered out goes with its buttons.
        var skippingHeader = false
        for child in Self.visualOrder(list.children()) {
            let role = child.stringAttribute(kAXRoleAttribute as String)
            if skippingHeader, role == (kAXButtonRole as String) { continue }
            skippingHeader = false
            if let sub = child.stringAttribute(kAXSubroleAttribute as String), AppNameResolver.bannerSubroles.contains(sub) {
                guard let row = Self.readRow(child, subrole: sub) else { continue }
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
        let next = NCPanelSnapshot.build(from: entries)
        mapElements(entries: entries, elements: elements)
        if next != snapshot {
            if Self.timing { // DEBUG-CLICK
                let rows = next.sections.flatMap(\.groups).flatMap(\.rows).map { "\($0.title):\($0.isStack ? "stack" : "row"):\(Int($0.height))" }
                FileHandle.standardError.write(Data("[snapshot] \(rows) uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
            }
            snapshot = next
        }
    }

    /// The buttons under the list: Edit Widgets, and the ✕ with its Clear Notifications
    /// menu, which is only there while there is something to clear (measured on 27.0).
    private func readFooter(in window: AXUIElement) {
        guard let scroll = Self.find(in: window, depth: 0, { $0.stringAttribute(kAXRoleAttribute as String) == (kAXScrollAreaRole as String) })
        else { return }
        let kids = scroll.children()
        editWidgetsButton = kids.first { $0.identifier == "widget-editor-button" }
        clearMenuButton = kids.first { $0.stringAttribute(kAXRoleAttribute as String) == "AXMenuButton" && $0.identifier == "xmark" }
        let next = NCPanelFooter(editWidgets: editWidgetsButton.flatMap { $0.stringAttribute("AXAttributedDescription") },
                                 clear: clearMenuButton.flatMap { $0.stringAttribute(kAXTitleAttribute as String) })
        if next != footer { footer = next }
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
        let field = NotificationActions.replyField(in: el)
        // The time is the one text without an identifier; title, subtitle and body have one.
        let time = el.children().first {
            $0.stringAttribute(kAXRoleAttribute as String) == (kAXStaticTextRole as String) && $0.identifier == nil
        }.flatMap { $0.stringAttribute(kAXValueAttribute as String) }.map(cleanAXString).flatMap { $0.isEmpty ? nil : $0 }
        return NCPanelRow(id: id, appName: appName, title: lines["title"] ?? "", subtitle: lines["subtitle"] ?? "",
                          body: lines["body"] ?? "", isStack: subrole.hasSuffix("Stack"),
                          actions: NotificationActions.appActions(of: el),
                          reply: field.map { $0.stringAttribute(kAXValueAttribute as String) ?? "" },
                          replyPlaceholder: field?.stringAttribute(kAXPlaceholderValueAttribute as String) ?? "",
                          expanded: NotificationActions.isExpanded(el),
                          height: el.size()?.height ?? 58, time: time)
    }

    // MARK: - Widgets

    private var showsWidgets: Bool {
        options.widgets && ScreenRecordingPermission.shared.isGranted
    }

    private func readWidgets() {
        guard showsWidgets, let window, let origin = window.point() else {
            if !widgets.isEmpty { widgets = [] }
            return
        }
        var found: [(String, AXUIElement)] = []
        Self.collectWidgets(in: window, into: &found)
        let previous = Dictionary(widgets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var next: [NCWidget] = []
        for (id, el) in found {
            guard let p = el.point(), let size = el.size() else { continue }
            let frame = CGRect(x: p.x - origin.x, y: p.y - origin.y, width: size.width, height: size.height)
            next.append(NCWidget(id: id, frameInWindow: frame, image: previous[id]?.image))
        }
        widgetElements = Dictionary(found, uniquingKeysWith: { a, _ in a })
        if next.map(\.id) != widgets.map(\.id) || next.map(\.frameInWindow) != widgets.map(\.frameInWindow) {
            widgets = next
        }
    }

    /// Panel widgets sit above the list; desktop widgets are windows of their own and are
    /// never in this window.
    private static func collectWidgets(in el: AXUIElement, into found: inout [(String, AXUIElement)], depth: Int = 0) {
        guard depth < 10 else { return }
        if let id = el.identifier, id.hasPrefix("widget-local:") {
            found.append((id, el))
            return
        }
        if el.identifier == "AXNotificationListItems" { return }
        for child in el.children() { collectWidgets(in: child, into: &found, depth: depth + 1) }
    }

    /// The part of Notification Center's window that draws something: the panel's column.
    private func panelContentRect() -> CGRect? {
        guard let window, let origin = window.point(),
              let scroll = Self.find(in: window, depth: 0, { $0.stringAttribute(kAXRoleAttribute as String) == (kAXScrollAreaRole as String) })
        else { return nil }
        let frames = scroll.children().compactMap { el -> CGRect? in
            guard let p = el.point(), let s = el.size(), s.width > 0, s.height > 0 else { return nil }
            return CGRect(x: p.x - origin.x, y: p.y - origin.y, width: s.width, height: s.height)
        }
        return frames.dropFirst().reduce(frames.first) { $0?.union($1) }
    }

    private static func find(in el: AXUIElement, depth: Int, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        guard depth < 6 else { return nil }
        if match(el) { return el }
        for child in el.children() {
            if let found = find(in: child, depth: depth + 1, match) { return found }
        }
        return nil
    }

    /// Brings the real panel from parked to right under ours, so it is drawn and its
    /// widgets can be captured: first an opaque cover where it will land, then the move.
    private func startWidgets() {
        ScreenRecordingPermission.shared.refresh()
        if options.widgets, !ScreenRecordingPermission.shared.isGranted {
            logger.log("Widgets are on, but Screen Recording isn't allowed — leaving them out", level: .warn, tag: "Panel")
        }
        readWidgets()
        guard showsWidgets, !widgets.isEmpty, let content = panelContentRect() else { return }
        let ours = panel.window.frame
        guard let primary = NSScreen.screens.first else { return }
        // Ours in AX coordinates (top left origin).
        let oursTop = primary.frame.maxY - ours.maxY
        // Under our rows, top right to top right, wherever they are.
        let rows = CustomNCPanelController.rowsRect(in: ours, options: options)
        let target = CGPoint(x: rows.maxX - content.maxX, y: oursTop + (ours.maxY - rows.maxY) - content.minY)
        let landed = content.offsetBy(dx: target.x, dy: target.y)
        cover.show(axRect: landed.insetBy(dx: -4, dy: -4), below: panel.window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isActive else { return }
            self.desiredOrigin = target
            self.keepInPlace()
            self.captureWidgets()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.captureWidgets() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.widgetTimer = timer
        }
        logger.log("Showing \(widgets.count) widget(s)", tag: "Panel")
    }

    private func stopWidgets() {
        widgetTimer?.invalidate()
        widgetTimer = nil
        cover.hide()
        widgets = []
        widgetElements = [:]
    }

    /// Captures the widgets, unless they move meanwhile: the panel slides in when it opens,
    /// and a picture cut by where a widget was a moment earlier shows the wrong part of it.
    /// Then it tries again shortly.
    private func captureWidgets(retries: Int = 6) {
        guard isActive, let window, let id = PrivateWindowAPI.windowID(for: window) else { return }
        readWidgets()
        let rects = Dictionary(widgets.map { ($0.id, $0.frameInWindow) }, uniquingKeysWith: { a, _ in a })
        Task { @MainActor [weak self] in
            guard let self else { return }
            let images = await self.widgetCapture.capture(windowID: id, rects: rects)
            guard self.isActive else { return }
            self.readWidgets()
            let settled = self.widgets.allSatisfy { w in
                rects[w.id].map { abs($0.minX - w.frameInWindow.minX) < 1 && abs($0.minY - w.frameInWindow.minY) < 1 } ?? false
            }
            guard settled else {
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.captureWidgets(retries: retries - 1)
                    }
                }
                return
            }
            if images.count < rects.count {
                self.logger.log("Captured \(images.count) of \(rects.count) widget(s)", level: .warn, tag: "Panel")
            }
            for i in self.widgets.indices {
                if let image = images[self.widgets[i].id] { self.widgets[i].image = image }
            }
        }
    }

    /// A click on a widget's picture, `at` as a fraction of its size. Widgets offer nothing
    /// to Accessibility, so the click goes to the real widget, which is right under ours:
    /// for that one click our panel and the router let everything through, and a real
    /// click lands on Notification Center's own window, which doesn't close its panel.
    /// The pointer goes back to where it was.
    func click(_ widget: NCWidget, at fraction: CGPoint) {
        guard let window, let origin = window.point() else { return }
        let f = widget.frameInWindow
        let point = CGPoint(x: origin.x + f.minX + f.width * fraction.x, y: origin.y + f.minY + f.height * fraction.y)
        let back = CGEvent(source: nil)?.location
        panel.window.ignoresMouseEvents = true
        router.passThrough = true
        // A beat for the window server to stop sending clicks to ours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
            }
            if let back {
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.router.passThrough = false
                self.panel.window.ignoresMouseEvents = false
            }
        }
        logger.log("Widget clicked: \(widget.appBundleID ?? widget.id)", tag: "Panel")
    }

    // MARK: - Actions, passed back to Notification Center

    private var refreshBurst: [DispatchWorkItem] = []

    /// Reads the list again a few times after an action: Notification Center animates what
    /// an action changes, and its tree can catch up after the first read with no further
    /// event to say so. Expanding a stack read once looked like it did nothing.
    private func refreshSoon() {
        refreshBurst.forEach { $0.cancel() }
        refreshBurst = [0.05, 0.2, 0.45, 0.9].map { delay in
            let item = DispatchWorkItem { [weak self] in self?.refresh() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
    }

    /// What a click on the row does in Notification Center: opens the notification, or
    /// expands a collapsed stack.
    func activate(_ row: NCPanelRow) {
        menu = nil
        guard let el = rowElements[row.id] else { return }
        if !row.isStack, let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == row.appName }) {
            app.activate()
        }
        let pressed = AXUIElementPerformAction(el, kAXPressAction as CFString)
        let sinceOpen = Int((ProcessInfo.processInfo.systemUptime - openedAt) * 1000)
        logger.log("Row pressed \(sinceOpen) ms after opening: \(pressed.rawValue), \(rowElements.count) rows known", tag: "Panel")
        guard !row.isStack else {
            refreshSoon()
            // With a reply open, Notification Center spends the first press on closing it
            // and only the second expands the stack (measured on 27.0, scripts/panel-lab
            // `real-expand-while-reply`). One click should do what it says.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.isActive, let el = self.rowElements[row.id],
                      el.stringAttribute(kAXSubroleAttribute as String)?.hasSuffix("Stack") == true else { return }
                AXUIElementPerformAction(el, kAXPressAction as CFString)
                self.refreshSoon()
            }
            return
        }
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

    /// One of the app's buttons on the row. A reply opens Notification Center's own field
    /// and gives it the focus: what you type goes there, and ours shows it.
    func perform(_ action: String, on row: NCPanelRow) {
        menu = nil
        guard let el = rowElements[row.id] else { return }
        actions.perform(action, id: row.id, on: el) { [weak self] opensReply in
            guard let self else { return }
            self.refreshSoon()
            if opensReply { self.mirrorReplies() }
        }
        logger.log("Action \(action) on \(row.appName)", tag: "Panel")
    }

    /// The row's chevron: shows or hides its buttons, in Notification Center too.
    func toggleDetails(_ row: NCPanelRow) {
        menu = nil
        guard let el = rowElements[row.id] else { return }
        actions.toggleDetails(of: el)
        refreshSoon()
    }

    func sendReply(_ row: NCPanelRow) {
        guard let el = rowElements[row.id] else { return }
        actions.send(id: row.id, on: el)
        refreshSoon()
    }

    /// While a reply is open, what is typed shows in ours: only the replying rows are read
    /// again, ten times a second. Reading the whole list each time took 11 to 22 ms on the
    /// main thread (NN_TIMING=1), and the panel stuttered as the reply opened.
    private func mirrorReplies() {
        guard replyTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let replying = self.snapshot.sections.flatMap(\.groups).flatMap(\.rows).filter { $0.reply != nil }
                guard !replying.isEmpty else {
                    self.replyTimer?.invalidate()
                    self.replyTimer = nil
                    self.refresh()
                    return
                }
                for row in replying { self.refreshRow(row.id) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        replyTimer = timer
    }

    /// Reads one row again and puts it in place, the rest of the list as it was.
    private func refreshRow(_ id: String) {
        guard let el = rowElements[id], let sub = el.stringAttribute(kAXSubroleAttribute as String),
              let fresh = Self.readRow(el, subrole: sub) else { return }
        var next = snapshot
        for s in next.sections.indices {
            for g in next.sections[s].groups.indices {
                if let r = next.sections[s].groups[g].rows.firstIndex(where: { $0.id == id }) {
                    next.sections[s].groups[g].rows[r] = fresh
                }
            }
        }
        if next != snapshot { snapshot = next }
    }

    /// The row's ✕: Close for one notification, Clear All for a collapsed stack.
    func close(_ row: NCPanelRow) {
        menu = nil
        guard let el = rowElements[row.id] else { return }
        let done = el.performCustomAction(namedAnyOf: row.isStack ? NCActionNames.clearAll : NCActionNames.close)
            || el.performCustomAction(namedAnyOf: NCActionNames.close.union(NCActionNames.clearAll))
        if !done { logger.log("Notification has no Close action", level: .warn, tag: "Panel") }
        refreshSoon()
    }

    func collapse(_ group: NCPanelSnapshot.Group) {
        menu = nil
        guard let showLess = groupButtons[group.id]?.first else { return }
        AXUIElementPerformAction(showLess, kAXPressAction as CFString)
        refreshSoon()
    }

    func clear(_ group: NCPanelSnapshot.Group) {
        menu = nil
        if group.expanded, let clear = groupButtons[group.id]?.last {
            AXUIElementPerformAction(clear, kAXPressAction as CFString)
        } else {
            for row in group.rows { close(row) }
        }
        refreshSoon()
    }

    func clearAll(_ section: NCPanelSnapshot.Section) {
        menu = nil
        if let button = sectionButtons[section.id] {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        } else {
            for group in section.groups { clear(group) }
        }
        refreshSoon()
    }

    /// Edit Widgets under the list, as Notification Center's own: it closes the panel and
    /// opens the widget gallery.
    func editWidgets() {
        menu = nil
        guard let button = editWidgetsButton else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        refreshSoon()
    }

    // MARK: - Notification Center's menus

    /// A row's menu, as its ⋯ or a right click opens it in Notification Center: the app's
    /// buttons unless they are shown already, then Mute for 1 Hour, Mute for Today, Turn
    /// Off, Dismiss, Notification Settings… `anchor` is where it opens in the panel's view.
    ///
    /// Notification Center builds the menu, so it is asked for it: the real one is opened
    /// on the parked row, read, and closed again at once. It opens at the parked row's
    /// place pulled onto the screen, not where it was asked for, which is why ours is drawn
    /// instead; used at once, no frame of it was filmed (scripts/panel-lab `parked-menu`).
    func showMenu(for row: NCPanelRow, withAppActions: Bool, at anchor: CGPoint, trailing: Bool) {
        guard let el = rowElements[row.id] else { return }
        let target = NCMenus.target(of: el)
        readRealMenu(of: target) { [weak self] items in
            guard let self, self.isActive, var items else { return }
            if !withAppActions {
                // The buttons come first, then a separator.
                while let first = items.first, first.kind == .action, row.actions.contains(first.title) { items.removeFirst() }
                if items.first?.kind == .separator { items.removeFirst() }
            }
            guard !items.isEmpty else { return }
            self.menu = NCPanelMenu(target: .row(row.id), items: items, anchor: anchor, trailing: trailing)
        }
    }

    /// The app's buttons alone, as the Options pill of a hovered row lists them. Known
    /// already, so Notification Center isn't asked.
    func showOptions(for row: NCPanelRow, at anchor: CGPoint) {
        let items = row.actions.enumerated().map { NCMenuItem(kind: .action, title: $1, occurrence: 0) }
        guard !items.isEmpty else { return }
        menu = NCPanelMenu(target: .options(row.id), items: items, anchor: anchor, trailing: true)
    }

    /// The footer ✕: Clear Banners Only, Clear All Notifications.
    func showClearMenu(at anchor: CGPoint) {
        guard let button = clearMenuButton else { return }
        readRealMenu(of: button) { [weak self] items in
            guard let self, self.isActive, let items, !items.isEmpty else { return }
            self.menu = NCPanelMenu(target: .clear, items: items, anchor: anchor)
        }
    }

    func dismissMenu() { menu = nil }

    /// An item of a menu open in ours: the app's own buttons are used as their buttons are,
    /// so a reply opens; everything else is pressed in Notification Center's menu.
    func choose(_ item: NCMenuItem) {
        guard let open = menu else { return }
        menu = nil
        let rowID: String?
        switch open.target {
        case .row(let id), .options(let id): rowID = id
        case .clear: rowID = nil
        }
        if let rowID, let row = snapshot.sections.lazy.flatMap({ $0.groups }).flatMap({ $0.rows }).first(where: { $0.id == rowID }),
           item.kind == .action, row.actions.contains(item.title) {
            perform(item.title, on: row)
            return
        }
        let element: AXUIElement?
        switch open.target {
        case .row(let id), .options(let id): element = rowElements[id].map(NCMenus.target)
        case .clear: element = clearMenuButton
        }
        guard let element else { return }
        readRealMenu(of: element, press: item) { [weak self] _ in self?.refreshSoon() }
        logger.log("Menu item \(item.title)", tag: "Panel")
    }

    private func readRealMenu(of el: AXUIElement, press: NCMenuItem? = nil, _ done: @escaping ([NCMenuItem]?) -> Void) {
        guard let window else { done(nil); return }
        NCMenus.read(of: el, in: window, press: press, logger: logger, done)
    }
}

/// What Notification Center shows under its list, by its own names; nil where it shows
/// nothing.
struct NCPanelFooter: Equatable {
    var editWidgets: String?
    var clear: String?
}

/// A menu open in our panel.
struct NCPanelMenu: Identifiable, Equatable {
    enum Target: Equatable {
        /// A row's ⋯ or right click.
        case row(String)
        /// A hovered row's Options pill: the app's buttons.
        case options(String)
        /// The footer ✕.
        case clear
    }
    let id = UUID()
    let target: Target
    let items: [NCMenuItem]
    /// Where it hangs from in the panel's view: its top left corner, or with `trailing`
    /// its top right, as a button's menu at the right of a row opens.
    let anchor: CGPoint
    var trailing = false
}
