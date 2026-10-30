// Measures what a custom Notification Center panel would have to build on.
//
// The custom banner works because Notification Center keeps owning the banner:
// we read it through Accessibility, park its window off screen, draw our own,
// and send clicks back to the real one. This probe checks whether the open
// panel can be treated the same way, and answers one question per section:
//
//   1 open     how soon an open panel can be detected after the clock press
//   2 shape    the panel's tree: which attributes and actions each kind of
//              element has, and what the app element offers
//   3 list     whether every row is in the tree or only those in view, and
//              whether the list can be scrolled from outside
//   4 events   which AX notifications fire on open, expand, arrival, close
//   5 arrive   what a notification arriving while the panel is open does
//   6 park     whether the panel stays open with its window parked off
//              screen, whether actions still work there, and whether a
//              click on a non-activating panel of ours closes it
//   7 alpha    whether WindowServer accepts an alpha change on NC's window
//   8 toggle   whether AXExpanded can open and close the panel
//
// It posts its own rows from the notify-lab apps (build them first with
// scripts/notify-lab/build.sh), opens the panel with the menu bar clock for
// about half a minute, and only ever acts on Lab rows. Text of any other
// notification or widget is replaced by its length in the dump. At the end it
// closes the panel, puts NC's window back where it was, and clears the Lab
// apps' notifications.
//
//   scripts/panel-probe.sh [--rows N]     N rows per Lab app, default 12
//
// Output: build/panel-probe/report.txt and tree.txt. Needs Accessibility for
// the app running it. Quit NotificationNanny first: it would move the window.

import AppKit
import ApplicationServices

// MARK: AX helpers

func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ key: String) -> String? {
    guard let v = attr(e, key) else { return nil }
    if let s = v as? String { return s }
    if CFGetTypeID(v) == CFAttributedStringGetTypeID() { return CFAttributedStringGetString((v as! CFAttributedString)) as String }
    return nil
}
func point(_ e: AXUIElement) -> CGPoint? {
    guard let v = attr(e, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    AXValueGetValue(v as! AXValue, .cgPoint, &p)
    return p
}
func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = point(e), let v = attr(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    AXValueGetValue(v as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
func settable(_ e: AXUIElement, _ key: String) -> Bool {
    var b: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(e, key as CFString, &b) == .success && b.boolValue
}
func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func parent(_ e: AXUIElement) -> AXUIElement? {
    guard let v = attr(e, kAXParentAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}
func attributeNames(_ e: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyAttributeNames(e, &names)
    return (names as? [String] ?? []).sorted()
}
func rawActions(_ e: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(e, &names)
    return names as? [String] ?? []
}
func actionName(_ a: String) -> String { a.hasPrefix("Name:") ? String(a.dropFirst(5).prefix { $0 != "\n" }) : a }
func actions(_ e: AXUIElement) -> [String] { rawActions(e).map(actionName) }
func setPoint(_ e: AXUIElement, _ p: CGPoint) -> AXError {
    var p = p
    return AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
}
func r(_ c: CGRect?) -> String {
    guard let c else { return "?" }
    return "(\(Int(c.minX)),\(Int(c.minY)) \(Int(c.width))x\(Int(c.height)))"
}

let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterBannerStack",
                                   "AXNotificationCenterAlert", "AXNotificationCenterAlertStack"]
func label(_ e: AXUIElement) -> String { str(e, "AXAttributedDescription") ?? str(e, kAXDescriptionAttribute) ?? "" }
func isRow(_ e: AXUIElement) -> Bool { str(e, kAXSubroleAttribute).map(bannerSubroles.contains) ?? false }
func isLab(_ e: AXUIElement) -> Bool { label(e).hasPrefix("Lab ") }
func rows(in e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 16 else { return [] }
    if isRow(e) { return [e] }
    return children(e).flatMap { rows(in: $0, depth: depth + 1) }
}
func find(_ e: AXUIElement, depth: Int = 0, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    guard depth < 16 else { return nil }
    if match(e) { return e }
    for c in children(e) { if let f = find(c, depth: depth + 1, match) { return f } }
    return nil
}
func ancestor(_ e: AXUIElement, role: String) -> AXUIElement? {
    var cur = parent(e)
    for _ in 0..<16 {
        guard let c = cur else { return nil }
        if str(c, kAXRoleAttribute) == role { return c }
        cur = parent(c)
    }
    return nil
}
func isUUID(_ s: String) -> Bool { s.count == 36 && s.filter { $0 == "-" }.count == 4 }

// MARK: Output

let outDir = "build/panel-probe"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var report: [String] = []
func say(_ s: String = "") { print(s); report.append(s) }
func now() -> Double { ProcessInfo.processInfo.systemUptime }
func ms(_ d: Double) -> String { "\(Int((d * 1000).rounded())) ms" }
func spin(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

// MARK: Preconditions

var rowsPerApp = 12
if let i = CommandLine.arguments.firstIndex(of: "--rows"), i + 1 < CommandLine.arguments.count,
   let n = Int(CommandLine.arguments[i + 1]), n > 0 { rowsPerApp = n }

let osv = ProcessInfo.processInfo.operatingSystemVersion
say("macOS \(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion), \(rowsPerApp) rows per Lab app")
guard AXIsProcessTrusted() else { print("Grant Accessibility to the app running this, then re-run."); exit(1) }
guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.notificationnanny.app").isEmpty else {
    print("NotificationNanny is running. Quit it first: it moves the window this measures."); exit(1)
}
guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
    print("Notification Center is not running."); exit(1)
}
let labApps = ["Alpha", "Bravo", "Charlie"]
func notifier(_ app: String) -> String { "build/notify-lab/Lab \(app).app/Contents/MacOS/notifier" }
guard labApps.allSatisfy({ FileManager.default.isExecutableFile(atPath: notifier($0)) }) else {
    print("Build the lab apps first: scripts/notify-lab/build.sh"); exit(1)
}
// The click test in section 6 shows a panel of ours, which needs an app.
NSApplication.shared.setActivationPolicy(.accessory)
let ncApp = AXUIElementCreateApplication(nc.processIdentifier)
AXUIElementSetMessagingTimeout(ncApp, 2)

func expanded() -> Bool? { attr(ncApp, "AXExpanded") as? Bool }
func windows() -> [AXUIElement] { attr(ncApp, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
/// The fullscreen window the panel opens in; never a desktop widget, which is a
/// Notification Center window too.
func host() -> AXUIElement? {
    windows().filter { str($0, kAXSubroleAttribute) == "AXSystemDialog" }
        .max { (frame($0)?.width ?? 0) * (frame($0)?.height ?? 0) < (frame($1)?.width ?? 0) * (frame($1)?.height ?? 0) }
}
func widgetButton() -> AXUIElement? {
    for w in windows() { if let b = find(w, { str($0, kAXIdentifierAttribute) == "widget-editor-button" }) { return b } }
    return nil
}
func allRows() -> [AXUIElement] { windows().flatMap { rows(in: $0) } }
func labRows() -> [AXUIElement] { allRows().filter(isLab) }

guard expanded() != true, widgetButton() == nil else {
    print("Close the Notification Center panel first."); exit(1)
}

func post(_ app: String, _ title: String, _ body: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: notifier(app))
    p.arguments = [title, body]
    try? p.run()
    p.waitUntilExit()
}
func clearLab() {
    for app in labApps {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: notifier(app))
        p.arguments = ["--clear"]
        try? p.run()
        p.waitUntilExit()
    }
}
func pressClock() -> Bool {
    let system = AXUIElementCreateSystemWide()
    let right = Int(NSScreen.screens.first?.frame.maxX ?? 1700)
    for x in stride(from: right - 1, through: right - 400, by: -6) {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(x), 12, &el) == .success, let el,
              str(el, kAXIdentifierAttribute) == "com.apple.menuextra.clock" else { continue }
        return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }
    return false
}

// Whatever happens, NC's window goes back and the panel is closed.
var hostHome: CGPoint?
func restore() {
    if let home = hostHome, let h = host(), point(h) != home { _ = setPoint(h, home) }
    if expanded() == true || widgetButton() != nil { _ = pressClock(); spin(0.8) }
    if let home = hostHome, let h = host(), point(h) != home { _ = setPoint(h, home) }
}
signal(SIGINT) { _ in restore(); clearLab(); exit(130) }

// MARK: Events

let watched: [String] = [
    kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXWindowMovedNotification,
    kAXWindowResizedNotification, kAXMainWindowChangedNotification, kAXUIElementDestroyedNotification,
    kAXLayoutChangedNotification, kAXCreatedNotification, kAXValueChangedNotification,
    kAXTitleChangedNotification, kAXFocusedUIElementChangedNotification, kAXSelectedChildrenChangedNotification,
    kAXRowExpandedNotification, kAXRowCollapsedNotification, kAXRowCountChangedNotification,
    kAXResizedNotification, kAXMovedNotification, "AXExpandedChanged", "AXElementBusyChanged",
]
var phase = "seed"
var phaseStart: [String: Double] = [:]
var events: [(t: Double, phase: String, name: String)] = []
func begin(_ p: String) { phase = p; phaseStart[p] = now() }

var observer: AXObserver?
AXObserverCreate(nc.processIdentifier, { _, _, note, _ in
    events.append((now(), phase, note as String))
}, &observer)
var unsupported: [String] = []
if let observer {
    for n in watched where AXObserverAddNotification(observer, ncApp, n as CFString, nil) != .success {
        unsupported.append(n)
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
}

func eventSummary(_ p: String) -> String {
    let mine = events.filter { $0.phase == p }
    guard !mine.isEmpty else { return "  events: none" }
    let start = phaseStart[p] ?? mine[0].t
    var counts: [String: (n: Int, first: Double)] = [:]
    for e in mine { counts[e.name] = ((counts[e.name]?.n ?? 0) + 1, counts[e.name]?.first ?? e.t - start) }
    return counts.sorted { $0.value.first < $1.value.first }
        .map { "  events: \($0.key) ×\($0.value.n), first at \(ms($0.value.first))" }
        .joined(separator: "\n")
}

// MARK: Seed

print("Posting \(rowsPerApp * labApps.count) Lab notifications…")
for i in 1...rowsPerApp {
    for app in labApps { post(app, "Probe \(app) \(i)", "Panel probe row \(i) of \(rowsPerApp)") }
}
spin(2.5)
hostHome = host().flatMap(point)

// MARK: 1 open

say("\n== 1 open: how soon is an open panel detectable? ==")
begin("open")
let pressed = now()
guard pressClock() else { say("menu bar clock not found"); clearLab(); exit(1) }
var seenButton: Double?, seenExpanded: Double?, seenLabRow: Double?
var hostMoved: Double?
let homeAtPress = host().flatMap(point)
while now() - pressed < 3, seenButton == nil || seenExpanded == nil || seenLabRow == nil {
    if seenButton == nil, widgetButton() != nil { seenButton = now() - pressed }
    if seenExpanded == nil, expanded() == true { seenExpanded = now() - pressed }
    if seenLabRow == nil, !labRows().isEmpty { seenLabRow = now() - pressed }
    if hostMoved == nil, let p = host().flatMap(point), p != homeAtPress { hostMoved = now() - pressed }
    spin(0.005)
}
say("  Edit Widgets button:  \(seenButton.map(ms) ?? "not seen in 3 s")")
say("  AXExpanded true:      \(seenExpanded.map(ms) ?? "not seen in 3 s")")
say("  first Lab row in AX:  \(seenLabRow.map(ms) ?? "not seen in 3 s")")
say("  host window moved:    \(hostMoved.map(ms) ?? "no")")
spin(1.0)
say(eventSummary("open"))
guard expanded() == true || widgetButton() != nil else {
    say("Panel did not open; stopping."); restore(); clearLab(); exit(1)
}

// MARK: 2 shape

say("\n== 2 shape: the app element and every kind of element in the panel ==")
say("  app attributes: \(attributeNames(ncApp).joined(separator: ", "))")
say("  app actions: \(actions(ncApp).joined(separator: " | "))")
say("  app AXExpanded settable: \(settable(ncApp, "AXExpanded"))")
for w in windows() {
    say("  window \(str(w, kAXSubroleAttribute) ?? "?") \(r(frame(w))) posSettable=\(settable(w, kAXPositionAttribute)) sizeSettable=\(settable(w, kAXSizeAttribute))")
}

// The tree goes to tree.txt. Only Lab rows and short button labels keep their
// text; anything else is a real notification or widget and shows its length.
var tree: [String] = []
var kinds: [String: String] = [:]
var kindOrder: [String] = []
func shown(_ s: String?, keep: Bool) -> String? {
    guard let s, !s.isEmpty else { return nil }
    let one = s.replacingOccurrences(of: "\n", with: " ⏎ ")
    return keep ? "\"\(one.prefix(80))\"" : "‹\(s.count) chars›"
}
func walk(_ e: AXUIElement, depth: Int, keepText: Bool) {
    guard depth < 18 else { return }
    let role = str(e, kAXRoleAttribute) ?? "?"
    let sub = str(e, kAXSubroleAttribute)
    let id = str(e, kAXIdentifierAttribute)
    let keep = isRow(e) ? isLab(e) : keepText
    let isButton = role == (kAXButtonRole as String)
    let desc = shown(str(e, kAXDescriptionAttribute), keep: keep || (isButton && (str(e, kAXDescriptionAttribute)?.count ?? 99) <= 24))
    let value = shown(str(e, kAXValueAttribute), keep: keep)
    let title = shown(str(e, kAXTitleAttribute), keep: keep || isButton)
    var line = String(repeating: "  ", count: depth) + role
    if let sub { line += "/\(sub)" }
    if let id { line += " #\(isUUID(id) ? "uuid" : id)" }
    line += " \(r(frame(e)))"
    if let title { line += " title=\(title)" }
    if let desc { line += " desc=\(desc)" }
    if let value { line += " value=\(value)" }
    let acts = actions(e).filter { $0 != "AXShowMenu" }
    if !acts.isEmpty { line += " actions=[\(acts.joined(separator: ", "))]" }
    tree.append(line)

    let kind = [role, sub ?? "", id.map { isUUID($0) ? "uuid" : $0 } ?? ""].joined(separator: " ")
    if kinds[kind] == nil {
        kindOrder.append(kind)
        kinds[kind] = "attrs=[\(attributeNames(e).joined(separator: ", "))] actions=[\(acts.joined(separator: ", "))]"
            + " posSettable=\(settable(e, kAXPositionAttribute)) valueSettable=\(settable(e, kAXValueAttribute))"
    }
    for c in children(e) { walk(c, depth: depth + 1, keepText: keep) }
}
for w in windows() { walk(w, depth: 0, keepText: false) }
for k in kindOrder { say("  kind \(k): \(kinds[k]!)") }

// MARK: 3 list

say("\n== 3 list: is every row in the tree, and can it scroll? ==")
func labCount() -> (rows: Int, items: Int) {
    let rs = labRows()
    // A collapsed stack is one row standing for several notifications.
    return (rs.count, rs.reduce(0) { n, row in n + (str(row, kAXSubroleAttribute)?.hasSuffix("Stack") == true ? 0 : 1) })
}
let posted = rowsPerApp * labApps.count
say("  posted \(posted); collapsed: \(labRows().count) Lab rows, subroles \(Set(labRows().compactMap { str($0, kAXSubroleAttribute) }).sorted())")
begin("expand")
for app in labApps {
    if let stack = labRows().first(where: { label($0).hasPrefix("Lab \(app),") && str($0, kAXSubroleAttribute)?.hasSuffix("Stack") == true }) {
        let err = AXUIElementPerformAction(stack, kAXPressAction as CFString)
        say("  pressed Lab \(app) stack: \(err == .success ? "ok" : "error \(err.rawValue)")")
        spin(1.0)
    }
}
say(eventSummary("expand"))
let afterExpand = labRows()
say("  expanded: \(afterExpand.count) Lab rows in the tree, \(labCount().items) single notifications (of \(posted) posted)")
if let any = afterExpand.first, let scroll = ancestor(any, role: kAXScrollAreaRole as String), let view = frame(scroll) {
    let frames = afterExpand.compactMap(frame)
    let inside = frames.filter { view.intersects($0) }.count
    say("  scroll area \(r(view)): \(inside) Lab rows inside its viewport, \(frames.count - inside) outside")
    say("  scroll area attrs: \(attributeNames(scroll).joined(separator: ", "))")
    say("  scroll area actions: \(actions(scroll).joined(separator: " | "))")
    if let bar = attr(scroll, kAXVerticalScrollBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
        let bar = bar as! AXUIElement
        say("  scroll bar value=\(attr(bar, kAXValueAttribute) as? Double ?? -1) settable=\(settable(bar, kAXValueAttribute))")
    } else {
        say("  no vertical scroll bar element")
    }
    if let last = afterExpand.max(by: { (frame($0)?.maxY ?? 0) < (frame($1)?.maxY ?? 0) }) {
        let before = frame(last)
        let hasAction = rawActions(last).contains("AXScrollToVisible")
        let err = AXUIElementPerformAction(last, "AXScrollToVisible" as CFString)
        spin(0.6)
        say("  AXScrollToVisible on the lowest Lab row (listed: \(hasAction)): \(err == .success ? "ok" : "error \(err.rawValue)"), row \(r(before)) → \(r(frame(last)))")
        say("  after scrolling: \(labRows().count) Lab rows in the tree")
    }
} else {
    say("  no AXScrollArea above the Lab rows")
}

// MARK: 5 arrive (events counted under 4)

say("\n== 5 arrive: a notification while the panel is open ==")
begin("arrive")
let rowsBefore = labRows().count
post("Alpha", "Probe arrival", "Posted while the panel is open")
spin(2.0)
let arrival = labRows().filter { label($0).contains("Probe arrival") }
say("  Lab rows \(rowsBefore) → \(labRows().count); arrival found \(arrival.count)× \(arrival.map { "\(str($0, kAXSubroleAttribute) ?? "?") \(r(frame($0)))" })")
say(eventSummary("arrive"))

// MARK: 7 alpha (before parking, while the window is on screen)

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowAlpha")
func CGSSetWindowAlpha(_ connection: Int32, _ windowID: CGWindowID, _ alpha: Float) -> Int32

say("\n== 7 alpha: will WindowServer let us fade NC's window? ==")
if let h = host() {
    var wid: CGWindowID = 0
    let got = _AXUIElementGetWindow(h, &wid)
    if got == .success, wid != 0 {
        let off = CGSSetWindowAlpha(CGSMainConnectionID(), wid, 0)
        spin(0.3)
        let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]])?.first
        let reported = info?[kCGWindowAlpha as String] as? Double
        let back = CGSSetWindowAlpha(CGSMainConnectionID(), wid, 1)
        say("  window \(wid): set alpha 0 → \(off), WindowServer then reports alpha \(reported.map { "\($0)" } ?? "?"), set back → \(back)")
    } else {
        say("  no window ID for the host (\(got.rawValue))")
    }
}

// MARK: 6 park

say("\n== 6 park: does the panel survive being moved off screen? ==")
begin("park")
if let h = host(), let home = hostHome {
    let parked = CGPoint(x: home.x, y: -9999)
    let err = setPoint(h, parked)
    var closedAt: Double?
    let t = now()
    while now() - t < 2 {
        if closedAt == nil, expanded() == false { closedAt = now() - t }
        spin(0.05)
    }
    say("  park → \(err == .success ? "ok" : "error \(err.rawValue)"), window at \(point(h).map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?") after 2 s")
    say("  panel \(closedAt.map { "CLOSED after \(ms($0))" } ?? "stayed open for 2 s")")

    // Actions while parked: close our arrival row, a Lab row, through its Close action.
    if closedAt == nil, let row = labRows().first(where: { label($0).contains("Probe arrival") }) {
        let names: Set<String> = ["Close", "Clear", "Clear All"]
        if let a = rawActions(row).first(where: { names.contains(actionName($0)) }) {
            let e = AXUIElementPerformAction(row, a as CFString)
            spin(1.0)
            let gone = !labRows().contains { label($0).contains("Probe arrival") }
            say("  \(actionName(a)) on the arrival row while parked: \(e == .success ? "ok" : "error \(e.rawValue)"), row \(gone ? "gone" : "still there")")
        } else {
            say("  arrival row actions: \(actions(row))")
        }
    }

    // A click on a non-activating panel of ours, the way the custom panel would be used.
    if expanded() == true {
        let screen = NSScreen.screens[0].frame
        let rect = NSRect(x: screen.midX - 160, y: screen.midY - 50, width: 320, height: 100)
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = NSColor(white: 0.2, alpha: 0.95)
        let text = NSTextField(labelWithString: "Panel probe: click test")
        text.textColor = .white
        text.frame = NSRect(x: 20, y: 40, width: 280, height: 20)
        panel.contentView?.addSubview(text)
        panel.orderFrontRegardless()
        spin(0.4)
        let click = CGPoint(x: rect.midX, y: screen.maxY - rect.midY)
        // Only click if the frontmost window under the point is ours; anything else is the
        // user's. Asked of WindowServer: AX can't answer for our own process while we wait.
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let front = onScreen.first { info in
            guard let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
            return rect.contains(click) && (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
        }
        let hitPid = front?[kCGWindowOwnerPID as String] as? pid_t ?? 0
        guard hitPid == getpid() else {
            say("  click test skipped: our panel is not what is under the pointer (pid \(hitPid))")
            panel.orderOut(nil)
            _ = setPoint(h, home)
            restore(); clearLab()
            try? report.joined(separator: "\n").write(toFile: "\(outDir)/report.txt", atomically: true, encoding: .utf8)
            try? tree.joined(separator: "\n").write(toFile: "\(outDir)/tree.txt", atomically: true, encoding: .utf8)
            exit(2)
        }
        let back = CGEvent(source: nil)!.location
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: click, mouseButton: .left)!.post(tap: .cghidEventTap)
            usleep(60_000)
        }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)!.post(tap: .cghidEventTap)
        spin(0.8)
        say("  click on our non-activating panel: NC panel \(expanded() == true ? "stayed open" : "CLOSED")")
        panel.orderOut(nil)
    }
    _ = setPoint(h, home)
    spin(0.3)
    say("  window back at \(point(h).map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?") (home \(Int(home.x)),\(Int(home.y)))")
}
say(eventSummary("park"))

// MARK: 8 toggle

say("\n== 8 toggle: can AXExpanded open and close the panel? ==")
if !settable(ncApp, "AXExpanded") {
    say("  AXExpanded is not settable; only the clock opens it")
} else {
    if expanded() != true { _ = pressClock(); spin(1.0) }
    begin("close")
    let e1 = AXUIElementSetAttributeValue(ncApp, "AXExpanded" as CFString, kCFBooleanFalse)
    spin(1.0)
    say("  set false → \(e1.rawValue), panel \(expanded() == true ? "still open" : "closed")")
    say(eventSummary("close"))
    if expanded() == false {
        begin("reopen")
        let e2 = AXUIElementSetAttributeValue(ncApp, "AXExpanded" as CFString, kCFBooleanTrue)
        spin(1.0)
        say("  set true → \(e2.rawValue), panel \(expanded() == true ? "opened" : "stayed closed")")
        say(eventSummary("reopen"))
    }
}

// MARK: Close and clean up

begin("final-close")
if expanded() == true { _ = pressClock(); spin(1.0) }
say("\n== 4 events: close with the clock ==")
say(eventSummary("final-close"))
say("  observer refused: \(unsupported.isEmpty ? "none" : unsupported.joined(separator: ", "))")
restore()
clearLab()
spin(1.0)
let finalPos = host().flatMap(point)
say("\nPanel open at the end: \(expanded() == true). Window \(finalPos.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?"), started at \(hostHome.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?"). Lab rows left: \(labRows().count).")

try? report.joined(separator: "\n").write(toFile: "\(outDir)/report.txt", atomically: true, encoding: .utf8)
try? tree.joined(separator: "\n").write(toFile: "\(outDir)/tree.txt", atomically: true, encoding: .utf8)
print("\nWrote \(outDir)/report.txt and tree.txt")
