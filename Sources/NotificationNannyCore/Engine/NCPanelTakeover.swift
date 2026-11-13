import AppKit
@preconcurrency import ApplicationServices
import SwiftUI


/// Panel options and banner appearance shared by its rows.
struct NCPanelOptions: Equatable {
    var appFilter = false
    var animation: BannerAnimation = .default
    /// How large it is drawn, 1 being the system's size.
    var scale: CGFloat = 1
    var side: NCPanelSide = .right
    /// How much lower than the system's it starts, in points.
    var topOffset: CGFloat = 0
    /// How far across from its side's place, right being positive.
    var xOffset: CGFloat = 0
    /// Pictures of the real widgets; only acted on with Screen Recording allowed.
    var widgets = false
    /// The banners' text colour, nil for the system's.
    var textColor: Color? = nil
    var redact = false
}

/// A widget in Notification Center's panel, as a picture of the real one.
struct NCWidget: Identifiable {
    /// Stable widget identifier from Accessibility.
    let id: String
    /// Where it is in Notification Center's window, in points from the window's top left.
    var frameInWindow: CGRect
    var image: NSImage?

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
    /// Overrides the clicked clock's screen when panel placement follows banners.
    var preferredScreen: () -> NSScreen? = { nil }

    /// Called when the panel opens, before ours shows.
    var onBegin: (() -> Void)?
    /// Called after the panel closes, so the repositioner can place banners again.
    var onEnd: (() -> Void)?
    /// The tint a banner from the app gets, clear for none. Read by the panel's view.
    var tint: (String) -> Color = { _ in .clear }

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
    /// Desired native origin: parked, or barely visible for widget capture.
    private var desiredOrigin: CGPoint?
    private var widgetElements: [String: AXUIElement] = [:]
    private let widgetCapture = WidgetCapture()
    /// Reuse widget images across openings to avoid empty placeholders during the first capture.
    private var widgetImages: [String: NSImage] = [:]
    private var widgetTimer: Timer?
    private let actions = NotificationActions()
    /// Mirrors a reply while one is open: the typing goes to Notification Center's field.
    private var replyTimer: Timer?
    /// The footer's Edit Widgets and Clear Notifications, while the panel shows them.
    private var editWidgetsButton: AXUIElement?
    private var clearMenuButton: AXUIElement?
    /// Panel opening time in system uptime.
    private var openedAt: Double = 0
    private var goingHome: (window: AXUIElement, home: CGPoint, work: DispatchWorkItem)?
    // Delay restoration until the native exit animation ends, or the real panel flashes on screen.
    private static let closeAnimation: TimeInterval = 0.8

    /// NN_LAB_PANEL_FILTER limits screenshots to Lab apps so personal notifications stay private.
    private static let labFilter = ProcessInfo.processInfo.environment["NN_LAB_PANEL_FILTER"]

    /// Park above every screen in AX coordinates.
    private static let parkedY: CGFloat = -9999

    init(logger: NannyLogger) {
        self.logger = logger
    }

    /// Owned windows, including one awaiting restoration, must be left alone by the repositioner.
    func owns(_ window: AXUIElement) -> Bool {
        if isActive, let mine = self.window { return CFEqual(mine, window) }
        if let going = goingHome { return CFEqual(going.window, window) }
        return false
    }

    /// Handles panel events first; returns true when the repositioner has nothing more to do.
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

    func settingsChanged(enabled: Bool) {
        if !enabled, isActive { end(reason: "turned off", stillOpen: isPanelOpen()) }
        let next = readOptions()
        guard next != options else { return }
        options = next
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

    /// Take over only when Notification Center reports AXExpanded.
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
        // Only park fullscreen hosts; desktop widgets have separate windows owned by the same
        // process.
        return windows.filter { $0.stringAttribute(kAXSubroleAttribute as String) == "AXSystemDialog" }
            .max { ($0.size()?.width ?? 0) < ($1.size()?.width ?? 0) }
    }

    // MARK: Lifecycle

    private func begin() {
        guard let host = hostWindow(), let origin = host.point() else { return }
        window = host
        // A reopened panel still has its previous restore destination.
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
        // Park before other work to prevent a visible native frame.
        desiredOrigin = CGPoint(x: origin.x, y: Self.parkedY)
        keepInPlace()
        options = readOptions()
        let screen = preferredScreen() ?? Self.screen(atAXPoint: origin) ?? NSScreen.main ?? NSScreen.screens[0]
        onBegin?()
        refresh(now: true)
        // Keep the panel open while its position is dragged in Settings.
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

    /// Wait for the AX list before showing ours to avoid flashing an empty panel.
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
        if Self.timing {
            FileHandle.standardError.write(Data("[timing] panel shown \(Int((ProcessInfo.processInfo.systemUptime - openedAt) * 1000)) ms after Notification Center opened, \(snapshot.rowCount) rows\n".utf8))
        }
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
        // Keep rows and widgets through the exit animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + options.animation.outroDuration + 0.1) { [weak self] in
            guard let self, !self.isActive else { return }
            self.snapshot = .empty
            self.widgets = []
        }
        logger.log("Custom Notification Center closed (\(reason))", tag: "Panel")
    }

    /// Restore the native window before quitting so future banners cannot arrive off screen.
    func releaseForQuit() {
        guard isActive, let window, let home else { return finishClosing() }
        router.stop()
        _ = setPosition(window, home)
        isActive = false
        self.window = nil
        self.home = nil
        desiredOrigin = nil
    }

    /// Complete a pending native window restoration immediately when quitting.
    func finishClosing() {
        guard let going = goingHome else { return }
        going.work.cancel()
        goingHome = nil
        _ = setPosition(going.window, going.home)
    }

    /// Reapply the parked position if Notification Center restores its host.
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

    // MARK: Reading the list

    /// Refresh within 40 ms of the first event; debouncing to the last event would wait out the
    /// animation.
    private func scheduleRefresh() {
        if let pending = pendingRefresh, !pending.isCancelled { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingRefresh = nil
            self?.refresh()
        }
        pendingRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
    }

    /// NN_TIMING=1 reports list read durations.
    private static let timing = ProcessInfo.processInfo.environment["NN_TIMING"] == "1"

    private struct ListRead {
        /// The list's children that decide the layout, with their elements; nil with no list.
        var entries: [(NCListEntry, AXUIElement)]?
        var editWidgets: AXUIElement?
        var clearMenu: AXUIElement?
        var footer = NCPanelFooter()
    }

    /// Notification Center's own names and roles a read needs, taken on the main thread.
    private struct ReadNames {
        let subroles: Set<String>
        let builtIn: Set<String>
        let hideDetails: Set<String>
        let labFilter: String?
    }

    private var readNames: ReadNames {
        ReadNames(subroles: AppNameResolver.bannerSubroles, builtIn: NCActionNames.builtIn,
                  hideDetails: NCActionNames.hideDetails, labFilter: Self.labFilter)
    }

    /// Read AX lists off the main thread so large histories do not delay clicks, typing, or
    /// drawing.
    private static let readQueue = DispatchQueue(label: "com.notificationnanny.panel-read", qos: .userInteractive)
    private var reading = false
    private var readAgain = false

    /// Read synchronously when `now` is true so the opening panel has content before it shows.
    private func refresh(now: Bool = false) {
        readWidgets()
        guard let window else {
            if snapshot != .empty { snapshot = .empty }
            return
        }
        let names = readNames
        if now {
            apply(Self.read(window, names))
            return
        }
        // Coalesce events during an active read into one additional read.
        guard !reading else { readAgain = true; return }
        reading = true
        let started = ProcessInfo.processInfo.systemUptime
        Self.readQueue.async {
            let result = Self.read(window, names)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    self.reading = false
                    if Self.timing {
                        let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                        FileHandle.standardError.write(Data("[timing] panel read \(ms) ms off the main thread\n".utf8))
                    }
                    if self.isActive, let current = self.window, CFEqual(current, window) { self.apply(result) }
                    if self.readAgain {
                        self.readAgain = false
                        self.refresh()
                    }
                }
            }
        }
    }

    private func apply(_ read: ListRead) {
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            if Self.timing {
                let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                FileHandle.standardError.write(Data("[timing] panel apply \(ms) ms, \(snapshot.rowCount) rows\n".utf8))
            }
        }
        editWidgetsButton = read.editWidgets
        clearMenuButton = read.clearMenu
        if read.footer != footer { footer = read.footer }
        guard let pairs = read.entries else {
            if snapshot != .empty { snapshot = .empty }
            return
        }
        let entries = pairs.map(\.0)
        let next = NCPanelSnapshot.build(from: entries)
        mapElements(entries: entries, elements: pairs.map(\.1))
        if next != snapshot {
            if Self.timing {
                let rows = next.sections.flatMap(\.groups).flatMap(\.rows).map { "\($0.title):\($0.isStack ? "stack" : "row"):\(Int($0.height))" }
                FileHandle.standardError.write(Data("[snapshot] \(rows) uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
            }
            snapshot = next
        }
    }

    /// Reads the list and footer using AX only; safe off the main thread.
    private nonisolated static func read(_ window: AXUIElement, _ names: ReadNames) -> ListRead {
        var result = ListRead()
        // Read the footer separately: an empty panel may have no list, only Edit Widgets.
        if let scroll = find(in: window, depth: 0, { $0.stringAttribute(kAXRoleAttribute as String) == (kAXScrollAreaRole as String) }) {
            let kids = scroll.children()
            result.editWidgets = kids.first { $0.identifier == "widget-editor-button" }
            result.clearMenu = kids.first { $0.stringAttribute(kAXRoleAttribute as String) == "AXMenuButton" && $0.identifier == "xmark" }
            result.footer = NCPanelFooter(editWidgets: result.editWidgets.flatMap { $0.stringAttribute("AXAttributedDescription") },
                                          clear: result.clearMenu.flatMap { $0.stringAttribute(kAXTitleAttribute as String) })
        }
        guard let list = findList(in: window, subroles: names.subroles) else { return result }
        var entries: [(NCListEntry, AXUIElement)] = []
        // In a lab run, a header of an app filtered out goes with its buttons.
        var skippingHeader = false
        for child in visualOrder(list.children()) {
            let role = child.stringAttribute(kAXRoleAttribute as String)
            if skippingHeader, role == (kAXButtonRole as String) { continue }
            skippingHeader = false
            if let sub = child.stringAttribute(kAXSubroleAttribute as String), names.subroles.contains(sub) {
                guard let row = readRow(child, subrole: sub, names) else { continue }
                if let only = names.labFilter, !row.appName.hasPrefix(only) { continue }
                entries.append((.row(row), child))
            } else if role == "AXHeading" {
                let text = cleanAXString(child.stringAttribute("AXAttributedDescription")
                    ?? child.stringAttribute(kAXDescriptionAttribute as String) ?? "")
                if let only = names.labFilter, !text.hasPrefix(only) {
                    skippingHeader = true
                    continue
                }
                entries.append((.heading(text), child))
            } else if role == (kAXButtonRole as String) {
                entries.append((.button, child))
            }
        }
        result.entries = entries
        return result
    }

    /// Map AX elements to the same groups and sections built by NCPanelSnapshot.
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

    /// Sort by drawn position because AX order can put expanded headers above earlier rows.
    /// Keep header buttons immediately after their heading.
    nonisolated static func visualOrder(_ elements: [AXUIElement]) -> [AXUIElement] {
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

    private nonisolated static func findList(in el: AXUIElement, subroles: Set<String>, depth: Int = 0) -> AXUIElement? {
        guard depth < 8 else { return nil }
        if el.identifier == "AXNotificationListItems" { return el }
        // Rows sit inside the list; nothing to find below one.
        if let sub = el.stringAttribute(kAXSubroleAttribute as String), subroles.contains(sub) {
            return nil
        }
        for child in el.children() {
            if let found = findList(in: child, subroles: subroles, depth: depth + 1) { return found }
        }
        return nil
    }

    private nonisolated static func readRow(_ el: AXUIElement, subrole: String, _ names: ReadNames) -> NCPanelRow? {
        guard let id = el.identifier else { return nil }
        let description = el.stringAttribute("AXAttributedDescription") ?? ""
        let lines = el.identifiedTextValues()
        let appName = AppNameResolver.appName(fromDescription: description, title: lines["title"]) ?? "Notification"
        let field = NotificationActions.replyField(in: el)
        // The time is the one text without an identifier; title, subtitle and body have one.
        let time = el.children().first {
            $0.stringAttribute(kAXRoleAttribute as String) == (kAXStaticTextRole as String) && $0.identifier == nil
        }.flatMap { $0.stringAttribute(kAXValueAttribute as String) }.map(cleanAXString).flatMap { $0.isEmpty ? nil : $0 }
        return NCPanelRow(id: id, appName: appName, title: lines["title"] ?? "", subtitle: lines["subtitle"] ?? "",
                          body: lines["body"] ?? "", isStack: subrole.hasSuffix("Stack"),
                          actions: NotificationActions.appActions(of: el, builtIn: names.builtIn),
                          reply: field.map { $0.stringAttribute(kAXValueAttribute as String) ?? "" },
                          replyPlaceholder: field?.stringAttribute(kAXPlaceholderValueAttribute as String) ?? "",
                          expanded: NotificationActions.isExpanded(el, hideDetails: names.hideDetails),
                          height: el.size()?.height ?? 58, time: time)
    }

    // MARK: Widgets

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
        // Keep missing widgets for one second while a resize temporarily removes them from AX.
        let now = ProcessInfo.processInfo.systemUptime
        if found.isEmpty, !widgets.isEmpty {
            if widgetsMissingSince == nil { widgetsMissingSince = now }
            if now - (widgetsMissingSince ?? now) < 1 { return }
        }
        widgetsMissingSince = nil
        let previous = Dictionary(widgets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var next: [NCWidget] = []
        var elements: [String: AXUIElement] = [:]
        for (id, el) in found {
            guard let p = el.point(), let size = el.size() else { continue }
            let frame = CGRect(x: p.x - origin.x, y: p.y - origin.y, width: size.width, height: size.height)
            // A menu lifts a duplicate widget with the same identifier; keep the one at its
            // original position.
            if let i = next.firstIndex(where: { $0.id == id }) {
                if Self.timing {
                    FileHandle.standardError.write(Data("[widgets] \(id.prefix(40)) twice, at \(Int(next[i].frameInWindow.minY)) and \(Int(frame.minY))\n".utf8))
                }
                if previous[id]?.frameInWindow != frame { continue }
                next[i].frameInWindow = frame
                elements[id] = el
                continue
            }
            next.append(NCWidget(id: id, frameInWindow: frame, image: previous[id]?.image ?? widgetImages[id]))
            elements[id] = el
            // Delay capture while a resized widget redraws.
            if let before = previous[id]?.frameInWindow.size, before != frame.size {
                widgetCaptureHold = max(widgetCaptureHold, now + 0.9)
            }
        }
        widgetElements = elements
        if next.map(\.id) != widgets.map(\.id) || next.map(\.frameInWindow) != widgets.map(\.frameInWindow) {
            widgets = next
        }
    }

    /// Collect panel widgets only; desktop widgets live in separate windows.
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

    private nonisolated static func find(in el: AXUIElement, depth: Int, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        guard depth < 6 else { return nil }
        if match(el) { return el }
        for child in el.children() {
            if let found = find(in: child, depth: depth + 1, match) { return found }
        }
        return nil
    }

    /// Park above the highest screen with one empty pixel row visible so widgets still render.
    /// `screens` uses AX coordinates.
    static func drawnOffScreen(windowSize: CGSize, screens: [CGRect]) -> CGPoint? {
        guard windowSize.height > 1, let top = screens.min(by: { $0.minY < $1.minY }) else { return nil }
        let origin = CGPoint(x: top.minX, y: top.minY - windowSize.height + 1)
        let hidden = CGRect(x: origin.x, y: origin.y, width: windowSize.width, height: windowSize.height - 1)
        let seen = screens.contains { s in
            let i = s.intersection(hidden)
            return !i.isNull && i.width > 0 && i.height > 0
        }
        return seen ? nil : origin
    }

    /// Every screen's frame in AX coordinates (top left origin of the main display).
    private static var axScreens: [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.map { CGRect(x: $0.frame.minX, y: primary.frame.maxY - $0.frame.maxY,
                                             width: $0.frame.width, height: $0.frame.height) }
    }

    /// Align the native column under ours for a real widget click.
    private func underOurs() -> CGPoint? {
        guard let content = panelContentRect(), let primary = NSScreen.screens.first else { return nil }
        let ours = panel.window.frame
        // Ours in AX coordinates (top left origin).
        let oursTop = primary.frame.maxY - ours.maxY
        let rows = CustomNCPanelController.rowsRect(in: ours, options: options)
        return CGPoint(x: rows.maxX - content.maxX, y: oursTop + (ours.maxY - rows.maxY) - content.minY)
    }

    /// Keep the native window rendering and capture widgets every two seconds.
    private func startWidgets() {
        ScreenRecordingPermission.shared.refresh()
        if options.widgets, !ScreenRecordingPermission.shared.isGranted {
            logger.log("Widgets are on, but Screen Recording isn't allowed — leaving them out", level: .warn, tag: "Panel")
        }
        readWidgets()
        guard showsWidgets, !widgets.isEmpty, let window, let size = window.size() else { return }
        guard let target = Self.drawnOffScreen(windowSize: size, screens: Self.axScreens) else {
            logger.log("No place to draw Notification Center's widgets unseen — leaving them out", level: .warn, tag: "Panel")
            return
        }
        desiredOrigin = target
        keepInPlace()
        captureWidgets()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureWidgets() }
        }
        RunLoop.main.add(timer, forMode: .common)
        widgetTimer = timer
        logger.log("Showing \(widgets.count) widget(s)", tag: "Panel")
    }

    private func stopWidgets() {
        widgetTimer?.invalidate()
        widgetTimer = nil
        widgetElements = [:]
    }

    /// Retry when widgets move during capture; the old crop would show the wrong area.
    private func captureWidgets(retries: Int = 6) {
        if Self.timing, ProcessInfo.processInfo.systemUptime < widgetCaptureHold {
            FileHandle.standardError.write(Data("[widgets] capture held for \(Int((widgetCaptureHold - ProcessInfo.processInfo.systemUptime) * 1000)) ms more\n".utf8))
        }
        guard isActive, ProcessInfo.processInfo.systemUptime >= widgetCaptureHold,
              let window, let id = PrivateWindowAPI.windowID(for: window) else { return }
        readWidgets()
        let rects = Dictionary(widgets.map { ($0.id, $0.frameInWindow) }, uniquingKeysWith: { a, _ in a })
        Task { @MainActor [weak self] in
            guard let self else { return }
            let started = ProcessInfo.processInfo.systemUptime
            let images = await self.widgetCapture.capture(windowID: id, rects: rects)
            if Self.timing {
                let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                FileHandle.standardError.write(Data("[timing] widget capture \(ms) ms, \(images.count) of \(rects.count)\n".utf8))
            }
            guard self.isActive else { return }
            self.readWidgets()
            let settled = self.widgets.allSatisfy { w in
                rects[w.id].map { abs($0.minX - w.frameInWindow.minX) < 1 && abs($0.minY - w.frameInWindow.minY) < 1 } ?? false
            }
            if !settled, Self.timing {
                FileHandle.standardError.write(Data("[widgets] capture dropped: widget moved meanwhile, \(retries) retries left\n".utf8))
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
                if let image = images[self.widgets[i].id] {
                    self.widgets[i].image = image
                    self.widgetImages[self.widgets[i].id] = image
                }
            }
        }
    }

    /// Forward a fractional click to the real widget, temporarily aligning the native panel under
    /// ours.
    /// Restore the pointer and parked window after the click.
    func click(_ widget: NCWidget, at fraction: CGPoint) {
        guard let under = underOurs() else { return }
        let parked = desiredOrigin
        desiredOrigin = under
        keepInPlace()
        let f = widget.frameInWindow
        let point = CGPoint(x: under.x + f.minX + f.width * fraction.x, y: under.y + f.minY + f.height * fraction.y)
        let back = CGEvent(source: nil)?.location
        panel.window.ignoresMouseEvents = true
        router.passThrough = true
        // Wait for the window server to apply positioning and click passthrough.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
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
            // A widget opening its app closes the panel; one that doesn't goes back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.isActive, self.desiredOrigin == under else { return }
                self.desiredOrigin = parked
                self.keepInPlace()
            }
        }
        logger.log("Widget clicked: \(widget.appBundleID ?? widget.id)", tag: "Panel")
    }

    // MARK: Actions, passed back to Notification Center

    private var refreshBurst: [DispatchWorkItem] = []

    /// Repeat reads after actions because AX may finish updating without another event.
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
            // An open reply consumes the first press; only then retry expansion to avoid toggling
            // an expanding stack shut.
            let replyOpen = snapshot.sections.contains { $0.groups.contains { $0.rows.contains { $0.reply != nil } } }
            guard replyOpen else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.isActive, let el = self.rowElements[row.id],
                      el.stringAttribute(kAXSubroleAttribute as String)?.hasSuffix("Stack") == true else { return }
                AXUIElementPerformAction(el, kAXPressAction as CFString)
                self.refreshSoon()
            }
            return
        }
        // Explicitly close the parked panel after opening a notification because it receives no
        // outside click.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isActive, self.isPanelOpen() else { return }
            if !Self.pressMenuBarClock() {
                self.logger.log("Couldn't find the menu bar clock to close Notification Center", level: .warn, tag: "Panel")
            }
        }
    }

    /// Presses the clock found by hit testing; on macOS 27 it belongs to MenuBarAgent.
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

    /// Performs an app action; replies focus the native field and mirror its text in ours.
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

    /// Toggle the native row's action buttons.
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

    /// Poll only replying rows at 10 Hz; rereading the full list stalls the main thread.
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
              let fresh = Self.readRow(el, subrole: sub, readNames) else { return }
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

    /// Close one notification, or Clear All for a collapsed stack.
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

    func editWidgets() {
        menu = nil
        guard let button = editWidgetsButton else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        refreshSoon()
    }

    // MARK: Notification Center's menus

    /// Mirrors a native row menu at `anchor`; omit app actions already shown as buttons. See
    /// NCMenus.
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

    /// Show known app actions without reopening the native menu.
    func showOptions(for row: NCPanelRow, at anchor: CGPoint) {
        let items = row.actions.enumerated().map { NCMenuItem(kind: .action, title: $1, occurrence: 0) }
        guard !items.isEmpty else { return }
        menu = NCPanelMenu(target: .options(row.id), items: items, anchor: anchor, trailing: true)
    }

    /// Cache widget menus to avoid exposing the native menu on each open; reopen only to select an
    /// item.
    func showMenu(for widget: NCWidget, at anchor: CGPoint) {
        if let items = widgetMenus[widget.id] {
            menu = NCPanelMenu(target: .widget(widget.id), items: items, anchor: anchor)
            return
        }
        guard let el = widgetElements[widget.id] else { return }
        frozen(for: widget) { [weak self] finished in
            self?.readRealMenu(of: el) { [weak self] items in
                finished()
                guard let self, self.isActive, let items, !items.isEmpty else { return }
                self.widgetMenus[widget.id] = items
                self.menu = NCPanelMenu(target: .widget(widget.id), items: items, anchor: anchor)
            }
        }
    }

    private let screenFreeze = ScreenFreeze()

    /// Hide the native widget menu behind ScreenFreeze until it closes and the panel is parked
    /// again.
    private func frozen(for widget: NCWidget, _ body: @escaping (@escaping () -> Void) -> Void) {
        let t0 = ProcessInfo.processInfo.systemUptime
        func trace(_ what: String) {
            guard Self.timing else { return }
            FileHandle.standardError.write(Data("[freeze] \(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) ms \(what), real window at \(self.window?.point().map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?")\n".utf8))
        }
        guard let rect = menuArea(for: widget) else { trace("no area"); body {}; return }
        trace("capturing \(Int(rect.rect.minX)),\(Int(rect.rect.minY)) \(Int(rect.rect.width))x\(Int(rect.rect.height))")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await self.screenFreeze.take(rect.rect, on: rect.screen)
            guard self.isActive else { return }
            let shown = image != nil
            if let image {
                // Raise our panel before the freeze image so it never obscures ours.
                self.panel.window.level = ScreenFreeze.panelLevel
                await self.screenFreeze.show(image, over: rect.rect)
            }
            trace("picture \(shown ? "up" : "FAILED"), panel level \(self.panel.window.level.rawValue), body")
            body { [weak self] in
                trace("real menu done")
                guard shown else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    guard let self else { return }
                    self.screenFreeze.hide()
                    self.panel.window.level = .statusBar
                    trace("picture gone")
                }
            }
        }
    }

    /// Freeze the widget's column across the full screen height, covering the lifted widget and
    /// menu.
    private func menuArea(for widget: NCWidget) -> (rect: NSRect, screen: NSScreen)? {
        guard let window, let origin = window.point() else { return nil }
        let x = origin.x + widget.frameInWindow.midX
        guard let screen = NSScreen.screens.first(where: { x >= $0.frame.minX && x < $0.frame.maxX }) else { return nil }
        let minX = max(screen.frame.minX, origin.x + widget.frameInWindow.minX - 60)
        return (NSRect(x: minX, y: screen.frame.minY, width: screen.frame.maxX - minX, height: screen.frame.height), screen)
    }

    /// When Notification Center last listed no widget while ours had some (system uptime).
    private var widgetsMissingSince: Double?

    /// Each widget's menu, by widget ID; see showMenu(for:at:).
    private var widgetMenus: [String: [NCMenuItem]] = [:]
    /// Capture deadline in system uptime; resizing widgets need time to finish drawing.
    private var widgetCaptureHold: Double = 0

    /// Shows the footer menu for clearing banners or all notifications.
    func showClearMenu(at anchor: CGPoint) {
        guard let button = clearMenuButton else { return }
        readRealMenu(of: button) { [weak self] items in
            guard let self, self.isActive, let items, !items.isEmpty else { return }
            self.menu = NCPanelMenu(target: .clear, items: items, anchor: anchor)
        }
    }

    func dismissMenu() { menu = nil }

    /// Route app actions through their reply handling; press other items in the native menu.
    func choose(_ item: NCMenuItem) {
        guard let open = menu else { return }
        menu = nil
        let rowID: String?
        switch open.target {
        case .row(let id), .options(let id): rowID = id
        case .clear, .widget: rowID = nil
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
        case .widget(let id): element = widgetElements[id]
        }
        guard let element else { return }
        if case .widget = open.target {
            widgetCaptureHold = ProcessInfo.processInfo.systemUptime + 0.7
        }
        let pressed: ([NCMenuItem]?) -> Void = { [weak self] items in
            guard let self else { return }
            self.refreshSoon()
            // Refresh the cached menu checkmark and capture the widget after it redraws.
            if case .widget(let id) = open.target {
                if let items { self.widgetMenus[id] = NCMenuItem.choosing(item, in: items) }
                for delay in [0.8, 1.6] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.captureWidgets() }
                }
            }
        }
        if case .widget(let id) = open.target, let widget = widgets.first(where: { $0.id == id }) {
            frozen(for: widget) { [weak self] finished in
                self?.readRealMenu(of: element, press: item) { items in
                    finished()
                    pressed(items)
                }
            }
        } else {
            readRealMenu(of: element, press: item, pressed)
        }
        logger.log("Menu item \(item.title)", tag: "Panel")
    }

    /// Park far off screen while reading menus so the native panel and menu cannot show through
    /// ours.
    private func readRealMenu(of el: AXUIElement, press: NCMenuItem? = nil, _ done: @escaping ([NCMenuItem]?) -> Void) {
        guard let window else { done(nil); return }
        let resting = desiredOrigin.flatMap { $0.y > Self.parkedY + 1 ? $0 : nil }
        if let resting {
            desiredOrigin = CGPoint(x: resting.x, y: Self.parkedY)
            keepInPlace()
        }
        NCMenus.read(of: el, in: window, press: press, logger: logger) { [weak self] items in
            done(items)
            guard let resting else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.isActive, self.desiredOrigin?.y == Self.parkedY else { return }
                self.desiredOrigin = resting
                self.keepInPlace()
                // Recapture after restoring a position where the widget renders.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.captureWidgets() }
            }
        }
    }
}

/// Native footer labels, nil when absent.
struct NCPanelFooter: Equatable {
    var editWidgets: String?
    var clear: String?
}

struct NCPanelMenu: Identifiable, Equatable {
    enum Target: Equatable {
        /// A row's menu button or secondary click.
        case row(String)
        /// A hovered row's Options pill: the app's buttons.
        case options(String)
        /// The footer clear menu.
        case clear
        case widget(String)
    }
    let id = UUID()
    let target: Target
    let items: [NCMenuItem]
    /// Menu anchor in panel coordinates; `trailing` anchors its top right corner.
    let anchor: CGPoint
    var trailing = false
}
