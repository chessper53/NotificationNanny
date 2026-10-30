// Panel lab: one experiment per question the custom Notification Center panel
// depends on. Run through run.sh, which builds it, posts Lab rows, films the
// flash runs and cleans up. Only Lab rows are ever acted on.
//
//   lab uuid             do a row's AXIdentifier, and a banner's, survive the panel
//                        closing and opening again?
//   lab flash native     open and close the panel without touching it (baseline)
//   lab flash react      park NC's window the moment the panel is seen open
//   lab flash prepark    park it before the clock press (needs a banner up, or
//                        there is no window to park)
//   lab tap              park the open panel, show a panel of ours, and catch
//                        clicks on it with an event tap before NC sees them;
//                        re-post them to us only. Does NC's panel stay open, and
//                        does our panel still get the click?
//   lab skin             a click-through panel of ours over the real one: do a
//                        click and a scroll still reach the real rows?
//   lab actions          what Show Details and Show do to a Lab stack
//   lab host             whether NC has a window right now (prints yes/no)
//
// Needs Accessibility for the app running it.

import AppKit
import ApplicationServices
import SwiftUI
@preconcurrency import ScreenCaptureKit

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
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
func setPoint(_ e: AXUIElement, _ p: CGPoint) -> AXError {
    var p = p
    return AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
}
func settable(_ e: AXUIElement, _ key: String) -> Bool {
    var b: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(e, key as CFString, &b) == .success && b.boolValue
}
func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func actionNames(_ e: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(e, &names)
    return names as? [String] ?? []
}
func displayName(_ a: String) -> String { a.hasPrefix("Name:") ? String(a.dropFirst(5).prefix { $0 != "\n" }) : a }
func perform(_ e: AXUIElement, named name: String) -> AXError? {
    guard let a = actionNames(e).first(where: { displayName($0) == name }) else { return nil }
    return AXUIElementPerformAction(e, a as CFString)
}

let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterBannerStack",
                                   "AXNotificationCenterAlert", "AXNotificationCenterAlertStack"]
func label(_ e: AXUIElement) -> String { str(e, "AXAttributedDescription") ?? "" }
func rows(in e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 16 else { return [] }
    if let s = str(e, kAXSubroleAttribute), bannerSubroles.contains(s) { return [e] }
    return children(e).flatMap { rows(in: $0, depth: depth + 1) }
}
func find(_ e: AXUIElement, depth: Int = 0, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    guard depth < 16 else { return nil }
    if match(e) { return e }
    for c in children(e) { if let f = find(c, depth: depth + 1, match) { return f } }
    return nil
}

func now() -> Double { ProcessInfo.processInfo.systemUptime }
func ms(_ d: Double) -> String { "\(Int((d * 1000).rounded())) ms" }
func spin(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

guard AXIsProcessTrusted(),
      let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
else { print("needs Accessibility, and Notification Center running"); exit(99) }
NSApplication.shared.setActivationPolicy(.accessory)
let ncApp = AXUIElementCreateApplication(nc.processIdentifier)
AXUIElementSetMessagingTimeout(ncApp, 2)

func windows() -> [AXUIElement] { attr(ncApp, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
/// The fullscreen window the banners and the panel live in. Never just the widest window:
/// each desktop widget is a Notification Center window too, and with the panel closed it
/// can be the only one, which once got a widget moved to the panel's place.
func host() -> AXUIElement? {
    windows().filter { str($0, kAXSubroleAttribute) == "AXSystemDialog" }
        .max { (frame($0)?.width ?? 0) < (frame($1)?.width ?? 0) }
}
func isOpen() -> Bool {
    if attr(ncApp, "AXExpanded") as? Bool == true { return true }
    return windows().contains { find($0) { str($0, kAXIdentifierAttribute) == "widget-editor-button" } != nil }
}
func labRows() -> [AXUIElement] { windows().flatMap { rows(in: $0) }.filter { label($0).hasPrefix("Lab ") } }
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
func waitFor(_ seconds: Double, step: Double = 0.005, _ cond: () -> Bool) -> Double? {
    let t = now()
    while now() - t < seconds {
        if cond() { return now() - t }
        spin(step)
    }
    return nil
}
func openPanel() -> Bool {
    guard !isOpen() else { return true }
    guard pressClock() else { return false }
    return waitFor(3) { isOpen() } != nil
}
func closePanel() {
    guard isOpen() else { return }
    _ = pressClock()
    _ = waitFor(3) { !isOpen() }
}

// Whatever happens, NC's window goes back where it was and the panel is closed.
var hostHome: CGPoint? = host().flatMap(frame)?.origin
func restore() {
    closePanel()
    if let home = hostHome, let h = host(), frame(h)?.origin != home { _ = setPoint(h, home) }
}
signal(SIGINT) { _ in restore(); exit(130) }

/// A real click at `point` (AX/CG coordinates, top-left origin), only if the frontmost
/// window there belongs to `owner`; anything else is the user's and is never clicked.
func click(at point: CGPoint, ifFrontIs owner: pid_t, skippingOurs: Bool = false) -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let front = list.first { info in
        if skippingOurs, info[kCGWindowOwnerPID as String] as? pid_t == getpid() { return false }
        guard let b = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
        return rect.contains(point) && (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
    }
    guard front?[kCGWindowOwnerPID as String] as? pid_t == owner else {
        print("  (not clicking: front window at the point is pid \(front?[kCGWindowOwnerPID as String] ?? "none"))")
        return false
    }
    let back = CGEvent(source: nil)!.location
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)!.post(tap: .cghidEventTap)
    return true
}

/// A panel of ours that counts the clicks it receives.
final class CountingView: NSView {
    var downs = 0
    override func mouseDown(with event: NSEvent) { downs += 1 }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
func makePanel(_ rect: NSRect, clickThrough: Bool) -> (NSPanel, CountingView) {
    let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: clickThrough ? 0.35 : 0.95)
    panel.ignoresMouseEvents = clickThrough
    let view = CountingView(frame: NSRect(origin: .zero, size: rect.size))
    let text = NSTextField(labelWithString: clickThrough ? "Panel lab: skin" : "Panel lab: click test")
    text.textColor = NSColor(calibratedRed: 1, green: 0.75, blue: 0.3, alpha: 1)
    text.frame = NSRect(x: 16, y: rect.height - 36, width: 260, height: 20)
    view.addSubview(text)
    panel.contentView = view
    panel.orderFrontRegardless()
    return (panel, view)
}
/// AX rect (top-left origin) to AppKit rect on the main display.
func appKitRect(_ r: CGRect) -> NSRect {
    NSRect(x: r.minX, y: NSScreen.screens[0].frame.maxY - r.maxY, width: r.width, height: r.height)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {

case "host":
    print(host() == nil ? "no" : "yes")

case "uuid":
    // A Lab banner's identifier while it is a banner, if one is up.
    let bannerIDs = Dictionary(labRows().compactMap { r in str(r, kAXIdentifierAttribute).map { ($0, label(r)) } },
                               uniquingKeysWith: { a, _ in a })
    print("Lab banners up before opening: \(bannerIDs.count)")
    func snapshot() -> [String: String] {
        Dictionary(labRows().compactMap { r in str(r, kAXIdentifierAttribute).map { ($0, label(r)) } },
                   uniquingKeysWith: { a, _ in a })
    }
    guard openPanel() else { print("panel did not open"); restore(); exit(1) }
    spin(0.6)
    let first = snapshot()
    closePanel(); spin(0.8)
    guard openPanel() else { print("panel did not reopen"); restore(); exit(1) }
    spin(0.6)
    let second = snapshot()
    closePanel()
    let same = Set(first.keys).intersection(second.keys).count
    print("rows: \(first.count) then \(second.count); identifiers kept: \(same) of \(first.count)")
    let byLabel1 = Dictionary(first.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
    for (id, l) in second where first[id] == nil {
        print("  changed: \(l.prefix(50)) \(byLabel1[l].map { "was \($0.prefix(8))" } ?? "new") now \(id.prefix(8))")
    }
    let fromBanner = Set(bannerIDs.keys).intersection(first.keys).count
    print("banner identifiers found again in the panel: \(fromBanner) of \(bannerIDs.count)")
    restore()

case "flash":
    let mode = args.dropFirst().first ?? "native"
    guard !isOpen() else { print("close the panel first"); exit(1) }
    var parkedAt: Double?
    if mode == "prepark" {
        guard let h = host(), let home = hostHome else { print("no window to park: nothing is up"); exit(2) }
        _ = setPoint(h, CGPoint(x: home.x, y: -9999))
        parkedAt = 0
    }
    spin(0.3)
    let pressed = now()
    print("press at \(String(format: "%.3f", Date().timeIntervalSince1970))")
    guard pressClock() else { print("no clock"); restore(); exit(1) }
    var seen: Double?
    while now() - pressed < 3 {
        if seen == nil, isOpen() { seen = now() - pressed }
        if mode == "react", seen != nil, parkedAt == nil, let h = host(), let home = hostHome ?? frame(h)?.origin {
            hostHome = home
            _ = setPoint(h, CGPoint(x: home.x, y: -9999))
            parkedAt = now() - pressed
        }
        if seen != nil, now() - pressed > (seen! + 1.2) { break }
        spin(0.002)
    }
    print("window after opening: \(host().flatMap(frame).map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? "none"), windows \(windows().count)")
    print("mode \(mode): open seen \(seen.map(ms) ?? "never"), parked \(parkedAt.map(ms) ?? "no")")
    restore()

case "tap":
    guard openPanel(), let h = host(), let home = hostHome ?? frame(h)?.origin else { print("panel did not open"); restore(); exit(1) }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.5)
    let screen = NSScreen.screens[0].frame
    let rect = NSRect(x: screen.midX - 160, y: screen.midY - 60, width: 320, height: 120)
    let (panel, view) = makePanel(rect, clickThrough: false)
    let cgRect = CGRect(x: rect.minX, y: screen.maxY - rect.maxY, width: rect.width, height: rect.height)

    // The tap swallows clicks inside our panel and re-posts them to this process only,
    // so no other app's monitor sees a click outside NC's panel.
    struct Tap {
        static var rect = CGRect.zero; static var swallowed = 0; static var tap: CFMachPort?
        static var panel: NSPanel?
    }
    Tap.rect = cgRect
    Tap.panel = panel
    let mask = CGEventMask((1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue))
    Tap.tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = Tap.tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard Tap.rect.contains(event.location) else { return Unmanaged.passUnretained(event) }
        Tap.swallowed += 1
        // Hand it to our panel ourselves, in its own coordinates; it never reaches the
        // window server's other listeners.
        if let panel = Tap.panel {
            let screenTop = NSScreen.screens[0].frame.maxY
            let p = NSPoint(x: event.location.x - panel.frame.minX,
                            y: (screenTop - event.location.y) - panel.frame.minY)
            let kind: NSEvent.EventType = type == .leftMouseDown ? .leftMouseDown : .leftMouseUp
            if let ns = NSEvent.mouseEvent(with: kind, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: 1, pressure: 1) {
                DispatchQueue.main.async { panel.sendEvent(ns) }
            }
        }
        return nil
    }, userInfo: nil)
    guard let machPort = Tap.tap else { print("could not create the event tap"); panel.orderOut(nil); restore(); exit(1) }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, machPort, 0), .commonModes)
    CGEvent.tapEnable(tap: machPort, enable: true)
    spin(0.4)
    let clicked = click(at: CGPoint(x: cgRect.midX, y: cgRect.midY), ifFrontIs: getpid())
    spin(0.8)
    print("tap: clicked \(clicked), swallowed \(Tap.swallowed), our view got \(view.downs) mouse down(s), NC panel \(isOpen() ? "STAYED OPEN" : "closed")")
    CGEvent.tapEnable(tap: machPort, enable: false)
    panel.orderOut(nil)
    restore()

case "skin":
    guard openPanel() else { print("panel did not open"); restore(); exit(1) }
    spin(0.6)
    guard let h = host(), let scroll = find(h, { str($0, kAXRoleAttribute) == (kAXScrollAreaRole as String) }),
          let area = frame(scroll) else { print("no scroll area"); restore(); exit(1) }
    let (panel, _) = makePanel(appKitRect(area), clickThrough: true)
    spin(0.4)
    // Click through our skin onto a collapsed Lab stack: pressing it expands it.
    let before = labRows().count
    if let stack = labRows().first(where: { str($0, kAXSubroleAttribute)?.hasSuffix("Stack") == true }),
       let f = frame(stack) {
        let target = CGPoint(x: f.midX, y: f.midY)
        // The skin ignores the mouse, so the front window that takes the click is NC's.
        let clicked = click(at: target, ifFrontIs: nc.processIdentifier, skippingOurs: true)
        spin(1.0)
        print("skin: clicked \(clicked) on \(label(stack).prefix(30)); Lab rows \(before) → \(labRows().count); NC panel \(isOpen() ? "open" : "CLOSED")")
    } else {
        print("skin: no collapsed Lab stack to click")
    }
    for stack in labRows() where str(stack, kAXSubroleAttribute)?.hasSuffix("Stack") == true {
        AXUIElementPerformAction(stack, kAXPressAction as CFString)
        spin(0.6)
    }
    var content: CGSize = .zero
    if let v = attr(scroll, "AXContentSize") { AXValueGetValue(v as! AXValue, .cgSize, &content) }
    print("skin: list \(labRows().count) Lab rows, content \(Int(content.height)) pt in a \(Int(area.height)) pt area")
    // A scroll wheel over the skin should move the real list.
    let firstRow = labRows().first.flatMap(frame)
    let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -200, wheel2: 0, wheel3: 0)!
    wheel.location = CGPoint(x: area.midX, y: area.midY)
    let back = CGEvent(source: nil)!.location
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: wheel.location, mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(80_000)
    wheel.post(tap: .cghidEventTap)
    spin(0.8)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)!.post(tap: .cghidEventTap)
    print("skin: scroll moved the first Lab row \(firstRow.map { "\(Int($0.minY))" } ?? "?") → \(labRows().first.flatMap(frame).map { "\(Int($0.minY))" } ?? "?")")
    let byPage = perform(scroll, named: "AXScrollDownByPage")
    spin(0.6)
    print("skin: AXScrollDownByPage \(byPage.map { "\($0.rawValue)" } ?? "missing"), first Lab row now \(labRows().first.flatMap(frame).map { "\(Int($0.minY))" } ?? "?")")
    panel.orderOut(nil)
    restore()

case "actions":
    guard openPanel() else { print("panel did not open"); restore(); exit(1) }
    spin(0.6)
    for name in ["Show Details", "Show"] {
        guard let stack = labRows().first(where: { r in actionNames(r).contains { displayName($0) == name } }) else {
            print("actions: no Lab row offers \(name)"); continue
        }
        let before = labRows().count
        let subrole = str(stack, kAXSubroleAttribute) ?? "?"
        let err = perform(stack, named: name)
        spin(1.0)
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        print("actions: \(name) on \(subrole) \(label(stack).prefix(30)) → \(err?.rawValue ?? -1); Lab rows \(before) → \(labRows().count); panel \(isOpen() ? "open" : "closed"); front app \(frontApp)")
        if !isOpen() { _ = openPanel(); spin(0.6) }
    }
    restore()

case "list":
    // The list's direct children, in order, after expanding one Lab stack while parked.
    // Only Lab rows and buttons/headings keep their text.
    guard openPanel(), let h = host(), let home = frame(h)?.origin else { print("panel did not open"); restore(); exit(1) }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.5)
    func dumpList(_ title: String) {
        print("-- \(title)")
        guard let list = find(h, { str($0, kAXIdentifierAttribute) == "AXNotificationListItems" }) else { print("no list"); return }
        for c in children(list) {
            let role = str(c, kAXRoleAttribute) ?? "?"
            let sub = str(c, kAXSubroleAttribute).map { "/\($0)" } ?? ""
            let d = label(c).isEmpty ? (str(c, kAXDescriptionAttribute) ?? "") : label(c)
            let lab = d.hasPrefix("Lab ")
            let chrome = role == "AXHeading" || role == "AXButton" || role == "AXMenuButton"
            let text = lab || chrome ? d.prefix(60).description : "<\(d.count) chars>"
            let acts = actionNames(c).map(displayName).filter { $0 != "AXShowMenu" }
            var kids = ""
            if !lab && !chrome { kids = "" } else {
                kids = children(c).map { k in
                    let kr = str(k, kAXRoleAttribute) ?? "?"
                    let kd = str(k, kAXIdentifierAttribute) ?? str(k, kAXDescriptionAttribute) ?? label(k)
                    return "\(kr):\(kd.prefix(20))"
                }.joined(separator: " ")
            }
            print("  \(role)\(sub) \(frame(c).map { "y=\(Int($0.minY)) h=\(Int($0.height))" } ?? "") \"\(text)\" [\(acts.joined(separator: ", "))] \(kids)")
        }
    }
    dumpList("collapsed")
    if let stack = labRows().first(where: { str($0, kAXSubroleAttribute)?.hasSuffix("Stack") == true }) {
        AXUIElementPerformAction(stack, kAXPressAction as CFString)
        spin(1.0)
        dumpList("after expanding \(label(stack).prefix(20)) (parked)")
    }
    restore()

case "ids":
    // Notes each Lab banner's identifier the first time it is up, for <seconds>, then
    // opens the panel parked, expands every Lab stack and says which rows were seen as
    // banners. Decides whether a time noted at the banner can be shown on its row.
    let seconds = Double(args.dropFirst().first ?? "8") ?? 8
    var seen: [String: (String, Double)] = [:]
    let start = now()
    while now() - start < seconds {
        for r in labRows() {
            guard let id = str(r, kAXIdentifierAttribute), seen[id] == nil else { continue }
            seen[id] = (label(r), now() - start)
            print(String(format: "  %5.2fs banner %@ %@ [%@]", now() - start, String(id.prefix(8)),
                         label(r), str(r, kAXSubroleAttribute) ?? "?"))
        }
        spin(0.05)
    }
    guard openPanel(), let h = host(), let home = frame(h)?.origin else { print("panel did not open"); restore(); exit(1) }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.4)
    for stack in labRows() where str(stack, kAXSubroleAttribute)?.hasSuffix("Stack") == true {
        AXUIElementPerformAction(stack, kAXPressAction as CFString)
        spin(0.6)
    }
    var matched = 0
    let rows = labRows()
    for r in rows {
        let id = str(r, kAXIdentifierAttribute) ?? "?"
        let was = seen[id]
        if was != nil { matched += 1 }
        print("  row \(id.prefix(8)) \(label(r)) [\(str(r, kAXSubroleAttribute) ?? "?")] \(was.map { "seen as banner at \(String(format: "%.2f", $0.1))s" } ?? "NEVER seen as banner")")
    }
    print("rows seen as banners: \(matched) of \(rows.count)")
    restore()

case "widgets":
    // Where widgets live: every NC window with the panel closed, then the open panel
    // (parked) outside its notification list. Text shows as its length only.
    func dumpTree(_ e: AXUIElement, depth: Int, maxDepth: Int, skipList: Bool, inWidget: Bool = false) {
        guard depth <= maxDepth else { return }
        let id = str(e, kAXIdentifierAttribute)
        if skipList, id == "AXNotificationListItems" {
            print(String(repeating: "  ", count: depth) + "[notification list, skipped]")
            return
        }
        let role = str(e, kAXRoleAttribute) ?? "?"
        let sub = str(e, kAXSubroleAttribute).map { "/\($0)" } ?? ""
        // --text shows widget text in full (widgets only; notifications are skipped anyway).
        let full = args.contains("--text") && (inWidget || (id ?? "").hasPrefix("widget-local:"))
        let texts = Array(Set([kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, "AXAttributedDescription"]
            .compactMap { str(e, $0) }.filter { !$0.isEmpty })).map { full ? "\"\($0)\"" : "<\($0.count)>" }
        let acts = actionNames(e).map(displayName).filter { $0 != "AXShowMenu" }
        let f = frame(e).map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? ""
        print(String(repeating: "  ", count: depth) + "\(role)\(sub)\(id.map { " #\($0.count == 36 ? "uuid" : $0)" } ?? "") \(f) \(texts.joined(separator: " ")) \(acts.isEmpty ? "" : "[\(acts.joined(separator: ", "))]")")
        let nowInWidget = inWidget || (id ?? "").hasPrefix("widget-local:")
        for c in children(e) { dumpTree(c, depth: depth + 1, maxDepth: maxDepth, skipList: skipList, inWidget: nowInWidget) }
    }
    print("== panel closed: \(windows().count) NC window(s)")
    for w in windows() { dumpTree(w, depth: 0, maxDepth: 9, skipList: true) }
    let cg = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let ncWins = cg.filter { $0[kCGWindowOwnerPID as String] as? pid_t == nc.processIdentifier }
    print("== CGWindowList for NC: \(ncWins.count) window(s)")
    for w in ncWins {
        let b = (w[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
        print("  #\(w[kCGWindowNumber as String] ?? "?") layer=\(w[kCGWindowLayer as String] ?? "?") onscreen=\(w[kCGWindowIsOnscreen as String] ?? false) (\(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))x\(Int(b.height)))")
    }
    let before = Set(windows().map { CFHash($0) })
    guard pressClock() else { print("no clock"); exit(1) }
    // Park the moment it opens, as the app does.
    guard waitFor(3, { isOpen() }) != nil, let h = host(), let home = frame(h)?.origin else { print("panel did not open"); restore(); exit(1) }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.8)
    print("== panel open (parked): \(windows().count) NC window(s), \(windows().filter { !before.contains(CFHash($0)) }.count) new")
    for w in windows() { dumpTree(w, depth: 0, maxDepth: 12, skipList: true) }
    restore()

case "widget-shot":
    // Can the parked panel's window be captured? Saves only the widgets' part of it to
    // <out>.png, cropped by their frames, so notifications never end up in the file.
    let out = args.dropFirst().first ?? "build/panel-lab/widget"
    guard pressClock(), waitFor(3, { isOpen() }) != nil, let h = host(), let home = frame(h)?.origin else {
        print("panel did not open"); restore(); exit(1)
    }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(1.0)
    guard let hf = frame(h),
          let widget = find(h, { (str($0, kAXIdentifierAttribute) ?? "").hasPrefix("widget-local:") }), let wf = frame(widget)
    else { print("no widget in the panel"); restore(); exit(1) }
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let wid = list.first { info in
        guard info[kCGWindowOwnerPID as String] as? pid_t == nc.processIdentifier,
              let b = info[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
        return abs(r.width - hf.width) < 2 && abs(r.height - hf.height) < 2
    }?[kCGWindowNumber as String] as? Int
    guard let wid else { print("no window number for the host"); restore(); exit(1) }
    let full = out + "-full.png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", "\(wid)", full]
    try? p.run(); p.waitUntilExit()
    // Crop to the widget, in points relative to the window; the image may be @2x.
    let rel = CGRect(x: wf.minX - hf.minX, y: wf.minY - hf.minY, width: wf.width, height: wf.height)
    print("window \(wid) at y \(Int(hf.minY)), widget at \(Int(rel.minX)),\(Int(rel.minY)) \(Int(rel.width))x\(Int(rel.height)) in it, capture exit \(p.terminationStatus)")
    if let img = NSImage(contentsOfFile: full), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let scale = CGFloat(cg.width) / hf.width
        let crop = CGRect(x: rel.minX * scale, y: rel.minY * scale, width: rel.width * scale, height: rel.height * scale)
        print("captured \(cg.width)x\(cg.height) (scale \(scale))")
        if let part = cg.cropping(to: crop) {
            let rep = NSBitmapImageRep(cgImage: part)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + ".png"))
            print("widget saved to \(out).png")
        }
    } else {
        print("nothing captured")
    }
    try? FileManager.default.removeItem(atPath: full)
    restore()

case "widget-cover":
    // The real panel left on screen under an opaque window of ours: can its widgets be
    // captured then, and does it stay hidden? Saves only the widgets' crop.
    let out = args.dropFirst().first ?? "build/panel-lab/widget-covered"
    guard let screen = NSScreen.screens.first else { exit(1) }
    // Below the menu bar: over it, the cover would hide the clock from the hit test.
    let coverRect = NSRect(x: screen.frame.maxX - 800, y: screen.visibleFrame.minY, width: 800, height: screen.visibleFrame.height)
    let cover = NSPanel(contentRect: coverRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    cover.level = .statusBar
    cover.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1)
    cover.orderFrontRegardless()
    spin(0.4)
    guard pressClock(), waitFor(3, { isOpen() }) != nil, let h = host(), let hf = frame(h) else {
        print("panel did not open"); cover.orderOut(nil); restore(); exit(1)
    }
    hostHome = hf.origin
    spin(1.0)
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let ncHost = list.first { info in
        guard info[kCGWindowOwnerPID as String] as? pid_t == nc.processIdentifier,
              let b = info[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
        return abs(r.width - hf.width) < 2
    }
    let ours = list.first { $0[kCGWindowOwnerPID as String] as? pid_t == getpid() }
    print("layers: NC host \(ncHost?[kCGWindowLayer as String] ?? "?"), our cover \(ours?[kCGWindowLayer as String] ?? "?"); front-to-back NC host is \(list.firstIndex { ($0[kCGWindowNumber as String] as? Int) == (ncHost?[kCGWindowNumber as String] as? Int) } ?? -1), ours \(list.firstIndex { $0[kCGWindowOwnerPID as String] as? pid_t == getpid() } ?? -1)")
    if let wid = ncHost?[kCGWindowNumber as String] as? Int,
       let widget = find(h, { (str($0, kAXIdentifierAttribute) ?? "").hasPrefix("widget-local:") }), let wf = frame(widget) {
        let full = out + "-full.png"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", "\(wid)", full]
        try? p.run(); p.waitUntilExit()
        if let img = NSImage(contentsOfFile: full), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let scale = CGFloat(cg.width) / hf.width
            let rel = CGRect(x: wf.minX - hf.minX, y: wf.minY - hf.minY, width: wf.width, height: wf.height)
            if let part = cg.cropping(to: CGRect(x: rel.minX * scale, y: rel.minY * scale, width: rel.width * scale, height: rel.height * scale)) {
                try? NSBitmapImageRep(cgImage: part).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + ".png"))
                print("widget captured under the cover → \(out).png")
            }
        } else {
            print("capture failed (exit \(p.terminationStatus))")
        }
        try? FileManager.default.removeItem(atPath: full)
    } else {
        print("no host window number or no widget")
    }
    closePanel()
    spin(0.3)
    cover.orderOut(nil)
    restore()

case "widget-hold":
    // The real panel open under a grey cover for 6 s, captured every 2 s by <mode>:
    // none, shot (screencapture -l) or sck (ScreenCaptureKit, as the app does). When,
    // if at all, does Notification Center close it? Nothing captured is kept.
    let mode = args.dropFirst().first ?? "none"
    guard let screen = NSScreen.screens.first else { exit(1) }
    let coverRect = NSRect(x: screen.frame.maxX - 800, y: screen.visibleFrame.minY, width: 800, height: screen.visibleFrame.height)
    let cover = NSPanel(contentRect: coverRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    cover.level = .statusBar
    cover.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1)
    cover.ignoresMouseEvents = true
    cover.orderFrontRegardless()
    spin(0.4)
    guard pressClock(), waitFor(3, { isOpen() }) != nil, let h = host(), let hf = frame(h) else {
        print("panel did not open"); cover.orderOut(nil); restore(); exit(1)
    }
    hostHome = hf.origin
    // move:dx,dy parks the window first, then brings it back on screen offset by that
    // much from where Notification Center had it, the way the app lines it up under ours.
    if mode.hasPrefix("move:") {
        let parts = mode.dropFirst(5).split(separator: ",").compactMap { Double($0) }
        _ = setPoint(h, CGPoint(x: hf.minX, y: -9999))
        spin(0.3)
        _ = setPoint(h, CGPoint(x: hf.minX + (parts.first ?? 0), y: hf.minY + (parts.last ?? 0)))
        print("  moved to (\(Int(hf.minX + (parts.first ?? 0))),\(Int(hf.minY + (parts.last ?? 0))))")
    }
    var wid: CGWindowID = 0
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    if let n = list.first(where: { info in
        guard info[kCGWindowOwnerPID as String] as? pid_t == nc.processIdentifier,
              let b = info[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
        return abs(r.width - hf.width) < 2
    })?[kCGWindowNumber as String] as? Int { wid = CGWindowID(n) }
    let start = now()
    var closedAt: Double?
    var lastShot = -10.0
    var shots = 0
    while now() - start < 6 {
        if closedAt == nil, !isOpen() { closedAt = now() - start; break }
        if mode != "none", !mode.hasPrefix("move:"), now() - lastShot >= 2 {
            lastShot = now()
            shots += 1
            if mode == "shot" {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", "\(wid)", "build/panel-lab/hold.png"]
                try? p.run(); p.waitUntilExit()
                try? FileManager.default.removeItem(atPath: "build/panel-lab/hold.png")
            } else {
                var done = false
                Task {
                    if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
                       let w = content.windows.first(where: { $0.windowID == wid }) {
                        let filter = SCContentFilter(desktopIndependentWindow: w)
                        let config = SCStreamConfiguration()
                        config.width = Int(w.frame.width); config.height = Int(w.frame.height)
                        _ = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    }
                    done = true
                }
                let t = now()
                while !done, now() - t < 3 { spin(0.02) }
                print(String(format: "  capture %d took %.0f ms, panel %@", shots, (now() - t) * 1000, isOpen() ? "open" : "CLOSED"))
            }
        }
        spin(0.05)
    }
    print("mode \(mode): \(shots) capture(s); panel \(closedAt.map { String(format: "CLOSED by itself after %.2f s", $0) } ?? "stayed open for 6 s")")
    closePanel()
    spin(0.3)
    cover.orderOut(nil)
    restore()

case "tree":
    // The whole open panel as Notification Center has it, every element with its role,
    // identifier, frame, actions and every attribute it has, left where it is. Text keeps
    // only in Lab rows and in the panel's own chrome (headings, buttons); the rest is its
    // length. `tree keep` leaves the panel open afterwards.
    guard openPanel() else { print("panel did not open"); exit(1) }
    spin(0.6)
    func describe(_ e: AXUIElement, depth: Int, inLab: Bool, inRow: Bool) {
        guard depth < 18 else { return }
        let role = str(e, kAXRoleAttribute) ?? "?"
        let sub = str(e, kAXSubroleAttribute)
        let isRow = sub.map { bannerSubroles.contains($0) } ?? false
        let lab = inLab || (isRow && label(e).hasPrefix("Lab "))
        let row = inRow || isRow
        let chrome = !row && (role == "AXHeading" || role == "AXButton" || role == "AXMenuButton" || role == "AXStaticText")
        func shown(_ s: String?) -> String? {
            guard let s, !s.isEmpty else { return nil }
            return lab || chrome ? "\"\(s.prefix(70))\"" : "<\(s.count)>"
        }
        var names: CFArray?
        AXUIElementCopyAttributeNames(e, &names)
        let skipped: Set<String> = [kAXRoleAttribute, kAXSubroleAttribute, kAXChildrenAttribute, kAXParentAttribute,
                                    kAXPositionAttribute, kAXSizeAttribute, kAXWindowAttribute,
                                    kAXTopLevelUIElementAttribute, "AXFrame"]
        let attrs = ((names as? [String]) ?? []).filter { !skipped.contains($0) }
        var parts = ["\(String(repeating: "  ", count: depth))\(role)\(sub.map { "/\($0)" } ?? "")"]
        if let id = str(e, kAXIdentifierAttribute) { parts.append("id=\(id.prefix(60))") }
        if let f = frame(e) { parts.append("@\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))") }
        for a in attrs where a != kAXIdentifierAttribute {
            guard let v = attr(e, a) else { continue }
            if let s = str(e, a) { if let t = shown(s) { parts.append("\(a)=\(t)") } }
            else if let b = v as? Bool { if b { parts.append("\(a)") } }
            else if let n = v as? NSNumber { parts.append("\(a)=\(n)") }
            else if CFGetTypeID(v) == CFDateGetTypeID() { parts.append("\(a)=DATE \(v)") }
            else if a != "AXChildrenInNavigationOrder" && a != "AXFocusableAncestor" { parts.append("\(a)=<\(CFCopyTypeIDDescription(CFGetTypeID(v)) as String? ?? "?")>") }
        }
        let acts = actionNames(e).map(displayName)
        if !acts.isEmpty { parts.append("[\(acts.joined(separator: ", "))]") }
        print(parts.joined(separator: " "))
        for c in children(e) { describe(c, depth: depth + 1, inLab: lab, inRow: row) }
    }
    print("app: expanded=\(attr(ncApp, "AXExpanded") as? Bool ?? false) actions=\(actionNames(ncApp))")
    for w in windows() { describe(w, depth: 0, inLab: false, inRow: false) }
    if args.dropFirst().first != "keep" { closePanel() }

case "real-hover":
    // The real panel, left on screen: rests the pointer on the Lab row whose title starts
    // with the argument, captures just that row before and while hovered, and prints its
    // subtree each time. `real-hover Title menu` then shows the row's menu (AXShowMenu on
    // its title, what a right click or the ⋯ does), prints the menu and captures it, and
    // cancels it. Only Lab rows are hovered, captured or acted on; the pointer goes back.
    let title = args.count > 1 ? args[1] : "Lab"
    guard openPanel() else { print("panel did not open"); exit(1) }
    spin(0.6)
    func labRow() -> AXUIElement? {
        labRows().first { r in children(r).contains { str($0, kAXValueAttribute)?.hasPrefix(title) == true } }
    }
    func subtree(_ e: AXUIElement, _ depth: Int = 1) {
        let f = frame(e).map { "@\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
        let text = str(e, kAXValueAttribute) ?? str(e, "AXAttributedDescription") ?? str(e, kAXTitleAttribute) ?? ""
        print("\(String(repeating: "  ", count: depth))\(str(e, kAXRoleAttribute) ?? "?") id=\(str(e, kAXIdentifierAttribute) ?? "-") \(f) \"\(text.prefix(50))\" [\(actionNames(e).map(displayName).joined(separator: ", "))]")
        for c in children(e) { subtree(c, depth + 1) }
    }
    func shot(_ rect: CGRect, _ name: String) {
        let r = rect.insetBy(dx: -24, dy: -16)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-R\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))", "build/panel-lab/\(name).png"]
        try? p.run(); p.waitUntilExit()
        print("  build/panel-lab/\(name).png")
    }
    guard let row = labRow(), let f = frame(row) else { print("no Lab row titled \(title)"); restore(); exit(1) }
    print("-- before hover"); subtree(row); shot(f, "real-row")
    let back = CGEvent(source: nil)!.location
    let inside = CGPoint(x: f.minX + 60, y: f.midY)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: inside.x - 30, y: inside.y), mouseButton: .left)!.post(tap: .cghidEventTap)
    spin(0.1)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: inside, mouseButton: .left)!.post(tap: .cghidEventTap)
    spin(1.0)
    if let row = labRow(), let f2 = frame(row) {
        print("-- hovered"); subtree(row); shot(f2.union(f), "real-row-hover")
    }
    if args.dropFirst(2).first == "menu", let row = labRow(),
       let text = children(row).first(where: { str($0, kAXIdentifierAttribute) == "title" }) {
        let before = Set(windows().map { CFHash($0) })
        let err = AXUIElementPerformAction(text, kAXShowMenuAction as CFString)
        spin(0.6)
        print("-- AXShowMenu: \(err.rawValue)")
        let menus = find(ncApp) { str($0, kAXRoleAttribute) == "AXMenu" }
        if let menu = menus {
            subtree(menu)
            if let mf = frame(menu) { shot(mf, "real-row-menu") }
            if AXUIElementPerformAction(menu, kAXCancelAction as CFString) != .success {
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
            }
        } else {
            print("no AXMenu under Notification Center; new windows: \(windows().filter { !before.contains(CFHash($0)) }.count)")
        }
        spin(0.4)
    }
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)!.post(tap: .cghidEventTap)
    if args.contains("keep") { break }
    restore()

case "parked-menu":
    // With the panel parked, does a Lab row's menu open, where, and does an item in it
    // reach the app? Picks the argument (default Snooze), which the Lab app logs.
    let item = args.count > 1 ? args[1] : "Snooze"
    guard openPanel(), let h = host(), let home = frame(h)?.origin else { print("panel did not open"); restore(); exit(1) }
    hostHome = home
    // `at=x,y`: parked there instead of straight up, the window's origin.
    let at = args.first { $0.hasPrefix("at=") }.map { a -> CGPoint in
        let v = a.dropFirst(3).split(separator: ",").compactMap { Double($0) }
        return CGPoint(x: v[0], y: v[1])
    }
    _ = setPoint(h, at ?? CGPoint(x: home.x, y: -9999))
    spin(0.5)
    guard let row = labRows().first(where: { r in item == "cancel" || actionNames(r).contains { displayName($0) == item } }),
          let text = children(row).first(where: { str($0, kAXIdentifierAttribute) == "title" })
    else { print("no Lab row offering \(item)"); restore(); exit(1) }
    print("pointer at \(CGEvent(source: nil)!.location)")
    let t0 = now()
    // The call waits for the menu to close; a short timeout lets it return at once.
    AXUIElementSetMessagingTimeout(text, 0.05)
    _ = AXUIElementPerformAction(text, kAXShowMenuAction as CFString)
    print("call returned after \(ms(now() - t0))")
    let menu = { find(ncApp) { str($0, kAXRoleAttribute) == "AXMenu" } }
    // `fast`: watched every millisecond and acted on at once, as the app would.
    _ = waitFor(2, step: args.contains("fast") ? 0.001 : 0.005) { menu() != nil }
    guard let m = menu() else { print("no menu"); restore(); exit(1) }
    print("menu after \(ms(now() - t0)) at \(frame(m).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "?")")
    print("on a screen: \(frame(m).map { f in NSScreen.screens.contains { appKitRect(f).intersects($0.frame) } } ?? false)")
    var chain: [String] = []
    var cur: AXUIElement? = m
    while let c = cur, let parent = attr(c, kAXParentAttribute) {
        let p = parent as! AXUIElement
        chain.append("\(str(p, kAXRoleAttribute) ?? "?")/\(str(p, kAXSubroleAttribute) ?? "-")")
        cur = p
    }
    print("menu's parents: \(chain)")
    print("app's children: \(children(ncApp).map { "\(str($0, kAXRoleAttribute) ?? "?")/\(str($0, kAXSubroleAttribute) ?? "-")" })")
    let items = children(m).compactMap { str($0, kAXTitleAttribute) }.filter { !$0.isEmpty }
    print("items: \(items)")
    if let t = children(row).first(where: { str($0, kAXIdentifierAttribute) == "title" }), let tf = frame(t) {
        print("title was at \(Int(tf.minX)),\(Int(tf.minY))")
    }
    if item == "cancel" {
        // AXCancel says yes and leaves it open; Escape closes it.
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    } else if let target = children(m).first(where: { str($0, kAXTitleAttribute) == item }) {
        print("press \(item): \(AXUIElementPerformAction(target, kAXPressAction as CFString).rawValue)")
    }
    spin(1.0)
    print("menu still open: \(menu() != nil); panel open: \(isOpen())")
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    print("NC windows on screen: \(list.filter { $0[kCGWindowOwnerPID as String] as? pid_t == nc.processIdentifier }.compactMap { $0[kCGWindowLayer as String] as? Int })")
    restore()

case "real-times":
    // The time Notification Center draws on each row: the row's one text without an
    // identifier. Prints the times only, never what a notification says.
    guard openPanel(), let h = host(), let home = frame(h)?.origin else { print("panel did not open"); restore(); exit(1) }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.5)
    for r in rows(in: h) {
        let time = children(r).first { str($0, kAXRoleAttribute) == kAXStaticTextRole && str($0, kAXIdentifierAttribute) == nil }
        let who = label(r).hasPrefix("Lab ") ? String(label(r).prefix(24)) : "(not Lab)"
        print("  \(str(r, kAXSubroleAttribute) ?? "?") \(who): \(time.flatMap { str($0, kAXValueAttribute) }.map { "\"\($0)\"" } ?? "no time")")
    }
    // The footer's ✕: its menu, opened and closed with Escape. Nothing in it is pressed.
    if let clear = find(h, { str($0, kAXRoleAttribute) == "AXMenuButton" && str($0, kAXIdentifierAttribute) == "xmark" }) {
        print("footer ✕: \(str(clear, kAXTitleAttribute) ?? "?") actions \(actionNames(clear))")
        AXUIElementSetMessagingTimeout(clear, 0.05)
        _ = AXUIElementPerformAction(clear, kAXShowMenuAction as CFString)
        _ = waitFor(2, step: 0.001) { find(ncApp) { str($0, kAXRoleAttribute) == "AXMenu" } != nil }
        if let m = find(h, { str($0, kAXRoleAttribute) == "AXMenu" }) ?? find(clear, { str($0, kAXRoleAttribute) == "AXMenu" }) {
            print("footer ✕ menu: \(children(m).compactMap { str($0, kAXTitleAttribute) }.filter { !$0.isEmpty })")
            var chain: [String] = []
            var cur: AXUIElement? = m
            while let c = cur, let parent = attr(c, kAXParentAttribute) {
                let p = parent as! AXUIElement
                chain.append("\(str(p, kAXRoleAttribute) ?? "?")/\(str(p, kAXIdentifierAttribute) ?? "-")")
                cur = p
            }
            print("its parents: \(chain)")
        } else { print("footer ✕ shows no menu") }
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        spin(0.3)
    }
    restore()

case "native-close":
    // Opens the real panel and closes it again with the clock, left alone, printing when
    // Notification Center says each happened; filmed from outside (see the notes).
    let t0 = now()
    guard openPanel() else { print("panel did not open"); exit(1) }
    print("open at \(ms(now() - t0))")
    spin(2.0)
    let t1 = now()
    _ = pressClock()
    _ = waitFor(3, step: 0.001) { !isOpen() }
    print("close pressed at \(ms(t1 - t0)), closed after \(ms(now() - t1))")
    spin(2.0)

case "close-timing":
    // How long Notification Center keeps drawing its panel after closing it: parks it,
    // closes it with the clock, and watches the window's contents go.
    guard openPanel(), let h = host(), let home = frame(h)?.origin else { print("panel did not open"); restore(); exit(1) }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.5)
    func hasList() -> Bool { find(h) { str($0, kAXIdentifierAttribute) == "AXNotificationListItems" } != nil }
    func hasScroll() -> Bool { find(h) { str($0, kAXRoleAttribute) == kAXScrollAreaRole } != nil }
    let t0 = now()
    _ = pressClock()
    var last = ""
    while now() - t0 < 2.5 {
        let s = "expanded=\(isOpen()) list=\(hasList()) scroll=\(hasScroll()) at=\(frame(h).map { "\(Int($0.minY))" } ?? "gone")"
        if s != last { print("  \(ms(now() - t0)): \(s)"); last = s }
        spin(0.01)
    }
    restore()

case "real-expand-while-reply":
    // The real panel, parked: opens the reply of the Lab row offering Reply, then presses
    // a Lab stack, as a click on it does. Does the stack expand, and at which press?
    guard openPanel(), let h = host(), let home = frame(h)?.origin else { print("panel did not open"); restore(); exit(1) }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.5)
    if let r = labRows().first(where: { actionNames($0).contains { displayName($0) == "Reply" } }) {
        print("reply: \(perform(r, named: "Reply")?.rawValue ?? 99)")
        spin(0.8)
    }
    func stack() -> AXUIElement? { labRows().first { str($0, kAXSubroleAttribute)?.hasSuffix("Stack") == true } }
    for press in 1...3 {
        guard let st = stack() else { print("expanded after \(press - 1) press(es)"); break }
        print("press \(press): \(AXUIElementPerformAction(st, kAXPressAction as CFString).rawValue)")
        spin(0.8)
        if stack() == nil { print("expanded after press \(press)"); break }
    }
    restore()

case "lab-banners":
    // The Lab banners on screen now, with the panel closed: their titles only.
    print(isOpen() ? "panel is open" : labRows().map { label($0).split(separator: ",").dropFirst().first.map(String.init) ?? "?" }.joined(separator: " |") )

case "shut":
    // Closes the panel only if it is open; a clock press on a closed one opens it.
    if isOpen() { _ = pressClock(); _ = waitFor(3) { !isOpen() } }
    print("panel \(isOpen() ? "still open" : "closed")")

case "act":
    // Triggers an action by name on the first Lab notification (banner or panel row),
    // then shows what is in Notification Center afterwards around it: whether a text
    // field appeared, and which buttons. Only Lab notifications are touched.
    let name = args.dropFirst().joined(separator: " ")
    guard let row = labRows().first(where: { r in actionNames(r).contains { displayName($0) == name } }) else {
        print("no Lab notification offers \(name)"); exit(1)
    }
    let t0 = now()
    let err = perform(row, named: name)
    print("\(name) → \(err?.rawValue ?? -1) after \(ms(now() - t0))")
    spin(1.0)
    func dumpAround(_ e: AXUIElement, _ d: Int) {
        guard d < 8 else { return }
        let role = str(e, kAXRoleAttribute) ?? "?"
        let lab = label(e).hasPrefix("Lab ")
        let interesting = ["AXTextField", "AXTextArea", "AXButton"].contains(role) || lab
        if interesting {
            let text = [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXPlaceholderValueAttribute]
                .compactMap { str(e, $0) }.filter { !$0.isEmpty }
            print(String(repeating: "  ", count: d) + "\(role)/\(str(e, kAXSubroleAttribute) ?? "") #\(str(e, kAXIdentifierAttribute) ?? "") \(frame(e).map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? "") \(text.map { "\"\($0.prefix(40))\"" }.joined(separator: " ")) [\(actionNames(e).map(displayName).joined(separator: ", "))] valueSettable=\(settable(e, kAXValueAttribute))")
        }
        for c in children(e) { dumpAround(c, d + 1) }
    }
    for w in windows() { dumpAround(w, 0) }
    // Every attribute of the reply field, to see where the app's placeholder is.
    if let field = find(row, { ["AXTextField", "AXTextArea"].contains(str($0, kAXRoleAttribute) ?? "") }) {
        var names: CFArray?
        AXUIElementCopyAttributeNames(field, &names)
        for n in (names as? [String]) ?? [] {
            if let v = str(field, n) { print("  field \(n) = \"\(v.prefix(40))\"") }
        }
        for c in children(field) { print("  field child \(str(c, kAXRoleAttribute) ?? "?") \(str(c, kAXValueAttribute) ?? str(c, kAXDescriptionAttribute) ?? "")") }
    }

case "reply-send":
    // Types into the reply field Notification Center showed for a Lab notification, and
    // sends it: by the field's own confirm action, or the Send button.
    let text = args.dropFirst().joined(separator: " ")
    var field: AXUIElement?
    for w in windows() {
        field = find(w) { ["AXTextField", "AXTextArea"].contains(str($0, kAXRoleAttribute) ?? "") }
        if field != nil { break }
    }
    guard let field else { print("no text field"); exit(1) }
    let set = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString)
    print("set value → \(set.rawValue), now \"\(str(field, kAXValueAttribute) ?? "")\"; field actions [\(actionNames(field).map(displayName).joined(separator: ", "))]")
    spin(0.3)
    if actionNames(field).contains("AXConfirm") {
        print("AXConfirm → \(AXUIElementPerformAction(field, "AXConfirm" as CFString).rawValue)")
    } else {
        var send: AXUIElement?
        for w in windows() {
            send = find(w) { str($0, kAXRoleAttribute) == "AXButton" && ["Send", "Senden"].contains(str($0, kAXDescriptionAttribute) ?? str($0, kAXTitleAttribute) ?? "") }
            if send != nil { break }
        }
        if let send { print("Send → \(AXUIElementPerformAction(send, kAXPressAction as CFString).rawValue)") } else { print("no Send button") }
    }
    spin(1.5)

case "type":
    // Focuses Notification Center's reply field for a Lab notification and types into it
    // with real keystrokes, but only once the system says that field has the keyboard
    // focus: otherwise the keys would land in whatever app is in front.
    let text = args.dropFirst().joined(separator: " ")
    var field: AXUIElement?
    for w in windows() {
        field = find(w) { ["AXTextField", "AXTextArea"].contains(str($0, kAXRoleAttribute) ?? "") }
        if field != nil { break }
    }
    guard let field else { print("no text field"); exit(1) }
    let focusErr = AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    spin(0.4)
    var focused: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
    let isOurs = focused.map { CFGetTypeID($0) == AXUIElementGetTypeID() && CFEqual($0, field) } ?? false
    var focusedApp: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &focusedApp)
    var appPid: pid_t = 0
    if let fa = focusedApp, CFGetTypeID(fa) == AXUIElementGetTypeID() { AXUIElementGetPid(fa as! AXUIElement, &appPid) }
    print("set focus → \(focusErr.rawValue); system focus is the reply field: \(isOurs); focused app pid \(appPid) (NC \(nc.processIdentifier)); frontmost \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    guard isOurs else { print("not typing: the keys would go elsewhere"); exit(2) }
    for ch in text.utf16 {
        var c = ch
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e.post(tap: .cghidEventTap)
        }
        usleep(15_000)
    }
    spin(0.4)
    print("field now \"\(str(field, kAXValueAttribute) ?? "")\"")

case "panel-reply":
    // The whole reply, in the open panel parked off screen: Reply on a Lab row, focus its
    // field, type with real keystrokes (only if the field has the focus), press Send.
    let text = args.dropFirst().joined(separator: " ")
    guard pressClock(), waitFor(3, { isOpen() }) != nil, let h = host(), let home = frame(h)?.origin else {
        print("panel did not open"); restore(); exit(1)
    }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.6)
    guard let row = labRows().first(where: { r in actionNames(r).contains { displayName($0) == "Reply" } }) else {
        print("no Lab row with Reply"); restore(); exit(1)
    }
    _ = perform(row, named: "Reply")
    spin(0.8)
    guard let field = find(h, { ["AXTextField", "AXTextArea"].contains(str($0, kAXRoleAttribute) ?? "") }) else {
        print("no reply field; panel \(isOpen() ? "open" : "CLOSED")"); restore(); exit(1)
    }
    AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    spin(0.4)
    var focused: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
    let isOurs = focused.map { CFGetTypeID($0) == AXUIElementGetTypeID() && CFEqual($0, field) } ?? false
    print("reply field focused: \(isOurs); panel \(isOpen() ? "open" : "CLOSED")")
    guard isOurs else { restore(); exit(2) }
    for ch in text.utf16 {
        var c = ch
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e.post(tap: .cghidEventTap)
        }
        usleep(15_000)
    }
    spin(0.4)
    print("field \"\(str(field, kAXValueAttribute) ?? "")\"; panel \(isOpen() ? "open" : "CLOSED")")
    if let send = find(h, { str($0, kAXRoleAttribute) == "AXButton" && str($0, kAXDescriptionAttribute) == "Send" }) {
        print("Send → \(AXUIElementPerformAction(send, kAXPressAction as CFString).rawValue)")
    }
    spin(1.0)
    print("after sending: panel \(isOpen() ? "open" : "closed")")
    restore()

case "unpark":
    // Puts Notification Center's window back on the main screen if something left it
    // parked: a NotificationNanny stopped by a script doesn't get to, and with nothing
    // running, banners would then arrive off screen.
    guard let h = host(), let p = frame(h)?.origin else { print("no window to unpark"); exit(0) }
    if p.y < -1000 || p.x < -1000 {
        let err = setPoint(h, .zero)
        print("unparked from (\(Int(p.x)),\(Int(p.y))) → \(err.rawValue)")
    } else {
        print("not parked (\(Int(p.x)),\(Int(p.y)))")
    }

case "hover-test":
    // Does hover reach a window of an app that isn't active, with a synthetic pointer
    // move? An AppKit tracking area (always active) against SwiftUI's onHover.
    final class Tracker: NSView {
        var entered = 0
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { entered += 1 }
    }
    final class Box { var swiftUI = 0 }
    let box = Box()
    let screen = NSScreen.screens[0].frame
    let rect = NSRect(x: screen.midX - 150, y: screen.midY - 50, width: 300, height: 100)
    let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .statusBar
    let host = NSHostingView(rootView: Color.gray.onHover { if $0 { box.swiftUI += 1 } })
    host.frame = NSRect(origin: .zero, size: rect.size)
    let tracker = Tracker(frame: NSRect(origin: .zero, size: rect.size))
    let container = NSView(frame: NSRect(origin: .zero, size: rect.size))
    container.addSubview(host)
    container.addSubview(tracker)
    panel.contentView = container
    panel.acceptsMouseMovedEvents = args.contains("--moved")
    panel.orderFrontRegardless()
    spin(0.4)
    var polledInside = false
    let poll = Timer(timeInterval: 0.03, repeats: true) { _ in
        if rect.contains(NSEvent.mouseLocation) { polledInside = true }
    }
    RunLoop.main.add(poll, forMode: .common)
    let back = CGEvent(source: nil)!.location
    let inside = CGPoint(x: rect.midX, y: screen.maxY - rect.midY)
    for p in [CGPoint(x: inside.x, y: inside.y - 200), CGPoint(x: inside.x, y: inside.y - 10), inside] {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
        spin(0.15)
    }
    spin(0.4)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)!.post(tap: .cghidEventTap)
    poll.invalidate()
    print("tracking area entered: \(tracker.entered), SwiftUI onHover: \(box.swiftUI), polled pointer inside: \(polledInside), acceptsMouseMoved \(panel.acceptsMouseMovedEvents)")
    panel.orderOut(nil)

case "panel-shots":
    // The real panel as it looks, for the replica: crops of the Lab rows only (and the
    // heading lines), with every frame written down. Nothing else of the panel is saved.
    let dir = args.dropFirst().first ?? "build/panel-lab/real"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var notes: [String] = []
    func shot(_ r: CGRect, _ name: String, pad: CGFloat = 4) {
        let c = r.insetBy(dx: -pad, dy: -pad)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-R\(Int(c.minX)),\(Int(c.minY)),\(Int(c.width)),\(Int(c.height))", "\(dir)/\(name).png"]
        try? p.run(); p.waitUntilExit()
    }
    func note(_ e: AXUIElement, _ what: String) {
        guard let f = frame(e) else { return }
        notes.append("\(what) (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)))")
    }
    func capture(_ stage: String) {
        guard let h = host(), let list = find(h, { str($0, kAXIdentifierAttribute) == "AXNotificationListItems" }) else { return }
        notes.append("-- \(stage)")
        var i = 0
        for c in children(list) {
            let role = str(c, kAXRoleAttribute) ?? "?"
            let d = label(c).isEmpty ? (str(c, kAXDescriptionAttribute) ?? "") : label(c)
            if d.hasPrefix("Lab ") {
                note(c, "row \(str(c, kAXSubroleAttribute) ?? "") \"\(d.prefix(40))\"")
                for k in children(c) { note(k, "   \(str(k, kAXRoleAttribute) ?? "?") #\(str(k, kAXIdentifierAttribute) ?? "")") }
                if let f = frame(c) { shot(f, "\(stage)-row\(i)"); i += 1 }
            } else if role == "AXHeading" || role == "AXButton" {
                note(c, "\(role) \"\(d)\"")
                // Heading lines hold no notification: the heading and its buttons.
                if role == "AXHeading", let f = frame(c), let lf = frame(list) {
                    shot(CGRect(x: lf.minX, y: f.minY, width: lf.width, height: f.height), "\(stage)-heading\(i)", pad: 3)
                    i += 1
                }
            }
        }
    }
    guard pressClock(), waitFor(3, { isOpen() }) != nil else { print("panel did not open"); restore(); exit(1) }
    spin(1.0)
    capture("collapsed")
    if let stack = labRows().first(where: { str($0, kAXSubroleAttribute)?.hasSuffix("Stack") == true }) {
        AXUIElementPerformAction(stack, kAXPressAction as CFString)
        spin(1.0)
        capture("expanded")
    }
    if let withButtons = labRows().first(where: { r in actionNames(r).contains { displayName($0) == "Show Details" } && actionNames(r).contains { displayName($0) == "Reply" } }) {
        _ = perform(withButtons, named: "Show Details")
        spin(0.8)
        capture("details")
    }
    closePanel()
    try? notes.joined(separator: "\n").write(toFile: "\(dir)/frames.txt", atomically: true, encoding: .utf8)
    print(notes.joined(separator: "\n"))

case "backdrop":
    // A plain gray window over everything but our panel, for <seconds>, so an on-screen
    // capture of the panel shows nothing of what is behind it on the user's screen.
    let parts = (args.dropFirst().first ?? "").split(separator: ",").compactMap { Double($0) }
    let seconds = Double(args.dropFirst(2).first ?? "3") ?? 3
    // Optional window level: just under ours by default; under Notification Center's (21)
    // to put it behind the real panel.
    let level = Int(args.dropFirst(3).first ?? "") ?? (NSWindow.Level.statusBar.rawValue - 1)
    guard parts.count == 4, let primary = NSScreen.screens.first else { print("usage: lab backdrop x,y,w,h seconds"); exit(64) }
    // Wide: glass blurs more than what is right under it, and a narrow backdrop let what
    // was on the screen around it shift the measurements from run to run.
    let pad = 150.0
    let rect = NSRect(x: parts[0] - pad, y: primary.frame.maxY - parts[1] - parts[3] - pad,
                      width: parts[2] + pad * 2, height: parts[3] + pad * 2)
    // A non-activating panel: a plain window showing up closes Notification Center's panel.
    let w = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    w.level = NSWindow.Level(rawValue: level)
    w.backgroundColor = NSColor(calibratedWhite: 0.42, alpha: 1)
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.orderFrontRegardless()
    spin(seconds)

case "app-actions":
    // Which buttons the notifications in Notification Center offer, per app: app names
    // and action names only, never what a notification says. The panel opens parked.
    guard pressClock(), waitFor(3, { isOpen() }) != nil, let h = host(), let home = frame(h)?.origin else {
        print("panel did not open"); restore(); exit(1)
    }
    hostHome = home
    _ = setPoint(h, CGPoint(x: home.x, y: -9999))
    spin(0.8)
    var seen: [String: Set<String>] = [:]
    for r in windows().flatMap({ rows(in: $0) }) {
        let app = label(r).components(separatedBy: ", ").first ?? "?"
        let acts = actionNames(r).map(displayName).filter { !["AXPress", "AXShowMenu", "AXScrollToVisible"].contains($0) }
        seen[app, default: []].formUnion(acts)
    }
    for (app, acts) in seen.sorted(by: { $0.key < $1.key }) { print("\(app): \(acts.sorted().joined(separator: ", "))") }
    restore()

case "lab-rect":
    // The area of the open panel holding the Lab rows, from its top to below the last,
    // as screencapture -R wants it; the width of ours (its window). Nothing below the
    // Lab rows, where the user's own notifications are, is in it.
    guard let primary = NSScreen.screens.first else { exit(1) }
    let frames = labRows().compactMap(frame)
    guard let bottom = frames.map(\.maxY).max() else { print("no Lab rows"); exit(1) }
    let width = 8.0 + 344 + 16
    let x = primary.frame.maxX - width
    let top = 46.0 - 8
    print("\(Int(x)),\(Int(top)),\(Int(width)),\(Int(bottom + 16 + 8 - top))")

case "scrim-test":
    // Does Notification Center darken the screen while its panel is open, and where?
    // Gray patches just under its window, measured with the panel closed and open.
    guard let primary = NSScreen.screens.first else { exit(1) }
    let f = primary.frame
    let spots: [(String, CGRect)] = [
        ("left", CGRect(x: 60, y: f.height / 2, width: 120, height: 80)),
        ("middle", CGRect(x: f.width / 2 - 60, y: f.height / 2, width: 120, height: 80)),
        ("beside panel", CGRect(x: f.width - 520, y: 200, width: 120, height: 80)),
        ("bottom right", CGRect(x: f.width - 300, y: f.height - 160, width: 120, height: 80)),
    ]
    var patches: [NSPanel] = []
    for (_, r) in spots {
        let w = NSPanel(contentRect: NSRect(x: r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: 20)
        w.backgroundColor = NSColor(calibratedWhite: 0.42, alpha: 1)
        w.ignoresMouseEvents = true
        w.orderFrontRegardless()
        patches.append(w)
    }
    spin(0.6)
    func measure() -> [Double] {
        spots.map { _, r in
            let path = "build/panel-lab/scrim.png"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-R\(Int(r.minX) + 20),\(Int(r.minY) + 20),20,20", path]
            try? p.run(); p.waitUntilExit()
            defer { try? FileManager.default.removeItem(atPath: path) }
            guard let rep = NSImage(contentsOfFile: path).flatMap({ $0.tiffRepresentation }).flatMap(NSBitmapImageRep.init) else { return -1 }
            var t = 0.0, n = 0.0
            for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) { t += (c.redComponent + c.greenComponent + c.blueComponent) / 3; n += 1 }
            } }
            return t / max(n, 1) * 255
        }
    }
    let closed = measure()
    guard pressClock(), waitFor(3, { isOpen() }) != nil else { print("panel did not open"); exit(1) }
    spin(1.0)
    let open = measure()
    closePanel()
    for (i, (name, _)) in spots.enumerated() {
        print(String(format: "%-13@ closed %5.1f  open %5.1f  (x%.3f)", name as NSString, closed[i], open[i], open[i] / max(closed[i], 1)))
    }
    patches.forEach { $0.orderOut(nil) }

case "clock":
    exit(pressClock() ? 0 : 1)

// The ui-* commands drive NotificationNanny's own panel (pid as the second argument)
// through its accessibility tree, with real clicks.
case "ui-settings", "ui-sdrag":
    // ui-settings: opens NotificationNanny's Settings with its menu bar icon and picks the
    // Notification Center tab. ui-sdrag dx,dy: drags the panel's place on that tab's
    // preview by dx,dy points, with real pointer events, only where Settings is in front.
    guard args.count >= 2, let pid = pid_t(args[1]) else { print("usage: lab \(args[0]) <pid> [dx,dy]"); exit(64) }
    let nnApp = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(nnApp, 2)
    func settingsWindow() -> AXUIElement? {
        (attr(nnApp, kAXWindowsAttribute) as? [AXUIElement] ?? []).first { str($0, kAXTitleAttribute) == "NotificationNanny Settings" }
    }
    func texts(in w: AXUIElement) -> [(String, CGRect)] {
        func all(_ e: AXUIElement, _ d: Int) -> [AXUIElement] { d > 30 ? [] : [e] + children(e).flatMap { all($0, d + 1) } }
        return all(w, 0).compactMap { e in
            let t = str(e, kAXValueAttribute) ?? str(e, kAXTitleAttribute) ?? str(e, kAXDescriptionAttribute) ?? ""
            return t.isEmpty ? nil : frame(e).map { (t, $0) }
        }
    }
    if args[0] == "ui-settings" {
        if settingsWindow() == nil {
            guard let bar = attr(nnApp, "AXExtrasMenuBar"), let item = children(bar as! AXUIElement).first else {
                print("   no menu bar icon"); exit(1)
            }
            _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
            _ = waitFor(3) { settingsWindow() != nil }
        }
        guard let w = settingsWindow() else { print("   Settings didn't open"); exit(1) }
        spin(0.5)
        guard let tab = texts(in: w).first(where: { $0.0 == "Notification Center" }) else { print("   no Notification Center tab"); exit(1) }
        _ = click(at: CGPoint(x: tab.1.midX, y: tab.1.midY), ifFrontIs: pid)
        spin(0.6)
        print("   Settings on Notification Center")
    } else {
        guard let w = settingsWindow() else { print("   Settings isn't open"); exit(1) }
        let all = texts(in: w)
        // The card's title, not the sidebar's tab of the same name: the one right above the note.
        guard let note = all.first(where: { $0.0.hasSuffix("Drag it anywhere on the preview.") }),
              let header = all.filter({ $0.0 == "Position" && $0.1.maxY < note.1.minY && $0.1.minX > note.1.minX - 260 })
                .max(by: { $0.1.minY < $1.1.minY }) else { print("   no position card"); exit(1) }
        let reset = all.filter { $0.0 == "Reset" && $0.1.minY > header.1.maxY && $0.1.maxY < note.1.minY + 4 }.first
        let x = (header.1.minX + (reset?.1.maxX ?? header.1.minX + 560)) / 2
        let start = CGPoint(x: x, y: (header.1.maxY + note.1.minY) / 2)
        print("   aim \(Int(start.x)),\(Int(start.y)); Position \(header.1), note \(note.1), Reset \(reset.map { "\($0.1)" } ?? "none"), window \(frame(w).map { "\($0)" } ?? "?")")
        let d = args.count > 2 ? args[2].split(separator: ",").compactMap { Double($0) } : [0, 40]
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let front = list.first { info in
            guard let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
            return r.contains(start) && (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
        }
        guard front?[kCGWindowOwnerPID as String] as? pid_t == pid else { print("   (not dragging: Settings isn't in front there)"); exit(1) }
        let back = CGEvent(source: nil)!.location
        func post(_ t: CGEventType, _ p: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start); usleep(80_000)
        post(.leftMouseDown, start); usleep(80_000)
        for i in 1...12 {
            post(.leftMouseDragged, CGPoint(x: start.x + d[0] * Double(i) / 12, y: start.y + d[1] * Double(i) / 12))
            usleep(30_000)
        }
        post(.leftMouseUp, CGPoint(x: start.x + d[0], y: start.y + d[1])); usleep(80_000)
        post(.mouseMoved, back)
        print("   dragged by \(Int(d[0])),\(Int(d[1])); NC panel \(isOpen() ? "open" : "CLOSED")")
    }

case "ui-clicktop":
    // Clicks the first row of our panel the moment its window is on screen, placed from
    // the window server's frame (the tree's frames lag right after it shows): 100 in from
    // its left, 28 down from its top, where the first row's title is with nothing above.
    guard args.count >= 2, let pid = pid_t(args[1]) else { print("usage: lab ui-clicktop <pid>"); exit(64) }
    let t0 = now()
    var spot: CGPoint?
    while spot == nil, now() - t0 < 3 {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where info[kCGWindowOwnerPID as String] as? pid_t == pid && (info[kCGWindowLayer as String] as? Int ?? 0) == 25 {
            guard let b = info[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b as CFDictionary),
                  r.width >= 350, r.height > 100 else { continue }
            spot = CGPoint(x: r.minX + 100, y: r.minY + 28)
        }
        if spot == nil { spin(0.005) }
    }
    guard let spot else { print("   our panel never showed"); exit(1) }
    print("   clicking \(Int((now() - t0) * 1000)) ms after the clock")
    exit(click(at: spot, ifFrontIs: pid) ? 0 : 1)

case "ui-menu":
    // A menu NotificationNanny has open (an NSMenu, not in any window): prints its items,
    // and presses the one named, if any.
    guard args.count >= 2, let pid = pid_t(args[1]) else { print("usage: lab ui-menu <pid> [item]"); exit(64) }
    let nnApp = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(nnApp, 2)
    guard let m = find(nnApp, { str($0, kAXRoleAttribute) == "AXMenu" && attr($0, kAXParentAttribute).map { str($0 as! AXUIElement, kAXRoleAttribute) != "AXMenuBarItem" } ?? true }) else {
        print("   no menu open"); exit(1)
    }
    let items = children(m)
    print("   menu: \(items.map { str($0, kAXTitleAttribute) ?? "" }.map { $0.isEmpty ? "—" : $0 }.joined(separator: " | "))")
    let want = args.dropFirst(2).joined(separator: " ")
    if !want.isEmpty {
        guard let hit = items.first(where: { str($0, kAXTitleAttribute) == want }) else { print("   no item \(want)"); exit(1) }
        print("   press \(want): \(AXUIElementPerformAction(hit, kAXPressAction as CFString).rawValue)")
    }

case "ui-state", "ui-click", "ui-close", "ui-button", "ui-winid", "ui-scroll", "ui-count", "ui-widget", "ui-hover", "ui-rect", "ui-rclick":
    guard args.count >= 2, let pid = pid_t(args[1]) else { print("usage: lab \(args[0]) <pid> [text]"); exit(64) }
    let nn = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(nn, 2)
    // Only the panel: custom banner overlays are windows of the app too, and can show
    // the same text. The panel is the largest. NN_LAB_TARGET=banners looks at the
    // banner overlays instead.
    let allNN = attr(nn, kAXWindowsAttribute) as? [AXUIElement] ?? []
    let nnWindows = ProcessInfo.processInfo.environment["NN_LAB_TARGET"] == "banners" ? allNN
        : allNN.max { (frame($0).map { $0.width * $0.height } ?? 0) < (frame($1).map { $0.width * $0.height } ?? 0) }
            .map { [$0] } ?? []
    func all(_ e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 30 else { return [] }
        return [e] + children(e).flatMap { all($0, depth: depth + 1) }
    }
    let elements = nnWindows.flatMap { all($0) }
    func text(_ e: AXUIElement) -> String {
        [str(e, kAXValueAttribute), str(e, kAXTitleAttribute), str(e, kAXDescriptionAttribute)]
            .compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }
    func role(_ e: AXUIElement) -> String { str(e, kAXRoleAttribute) ?? "" }
    let texts = elements.filter { role($0) == "AXStaticText" }
    switch args[0] {
    case "ui-winid":
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let mine = list.filter { $0[kCGWindowOwnerPID as String] as? pid_t == pid && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }
        func area(_ w: [String: Any]) -> CGFloat {
            (w[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
                .map { $0.width * $0.height } ?? 0
        }
        guard let top = mine.max(by: { area($0) < area($1) }), let id = top[kCGWindowNumber as String] as? Int else { print("none"); exit(1) }
        // `ui-winid <pid> frame`: where it is, rather than its number.
        if args.dropFirst(2).first == "frame", let b = top[kCGWindowBounds as String] as? NSDictionary,
           let r = CGRect(dictionaryRepresentation: b as CFDictionary) {
            print("   panel window: \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))")
        } else {
            print(id)
        }
    case "ui-rect":
        // Our panel's frame as screencapture -R wants it.
        guard let f = nnWindows.compactMap(frame).first else { print("none"); exit(1) }
        print("\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))")
    case "ui-state":
        let panelFrame = nnWindows.compactMap(frame).max { $0.height < $1.height }
        print("our panel: \(panelFrame.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? "none")")
        print("our texts: \(texts.map(text).filter { !$0.isEmpty }.joined(separator: " | "))")
        print("our buttons: \(elements.filter { role($0) == "AXButton" }.map(text).joined(separator: " | "))")
        print("NC panel open: \(isOpen()), NC window y: \(host().flatMap(frame).map { "\(Int($0.minY))" } ?? "none")")
        print("NC Lab rows: \(labRows().map { "\(str($0, kAXSubroleAttribute)?.replacingOccurrences(of: "AXNotificationCenter", with: "") ?? "?"):\(label($0).split(separator: ",").dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "?")" }.joined(separator: " | "))")
    case "ui-hover":
        // Rests the pointer on the text in our panel, and leaves it there.
        let want = args.dropFirst(2).joined(separator: " ")
        guard let t = texts.first(where: { text($0) == want }), let f = frame(t) else { print("no text \(want)"); exit(1) }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: f.midX, y: f.midY), mouseButton: .left)!
            .post(tap: .cghidEventTap)
        // An event posted right before the process exits can be dropped.
        usleep(150_000)
    case "ui-widget":
        // Clicks the middle of the first widget picture in our panel.
        guard let img = elements.filter({ role($0) == "AXImage" }).compactMap({ e in frame(e).map { (e, $0) } })
                .max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }), img.1.width > 100 else {
            print("no widget picture"); exit(1)
        }
        print("widget picture \(Int(img.1.width))x\(Int(img.1.height))")
        exit(click(at: CGPoint(x: img.1.midX, y: img.1.midY), ifFrontIs: pid) ? 0 : 1)
    case "ui-count":
        // Numbers only, for runs that show the user's own notifications.
        let allRows = windows().flatMap { rows(in: $0) }
        let ourButtons = elements.filter { role($0) == "AXButton" }.map(text)
        print("NC panel open: \(isOpen()), NC rows: \(allRows.count), our Clear All buttons: \(ourButtons.filter { $0 == "Clear All" }.count), our ✕ buttons: \(ourButtons.filter { $0 == "Close" }.count)")
    case "ui-scroll":
        // A scroll wheel over our panel: it must not close Notification Center's.
        guard let f = nnWindows.compactMap(frame).max(by: { $0.height < $1.height }) else { print("no panel"); exit(1) }
        let point = CGPoint(x: f.midX, y: f.midY)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let front = list.first { info in
            guard let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
            return r.contains(point)
        }
        guard front?[kCGWindowOwnerPID as String] as? pid_t == pid else { print("not ours under the pointer"); exit(1) }
        let back = CGEvent(source: nil)!.location
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        usleep(80_000)
        for _ in 0..<6 {
            let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -60, wheel2: 0, wheel3: 0)!
            wheel.location = point
            wheel.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        usleep(300_000)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)!.post(tap: .cghidEventTap)
        print("scrolled; NC panel \(isOpen() ? "open" : "CLOSED")")
    case "ui-click":
        // Clicks as soon as the text shows, for a click right after the panel opens.
        let want = args.dropFirst(2).joined(separator: " ")
        // The tree's frames lag when the window comes back at another size, so the text's
        // place is taken relative to its window there, and the window's from the window
        // server, which is always current.
        func findNow() -> CGRect? {
            let wins = (attr(nn, kAXWindowsAttribute) as? [AXUIElement] ?? [])
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            for w in wins {
                // Only the panel: a custom banner of the same notification shows the same
                // text until the panel opens. The panel is the one with Edit Widgets.
                let inside = all(w)
                guard inside.contains(where: { text($0) == "Edit Widgets" }) else { continue }
                guard let t = inside.first(where: { role($0) == "AXStaticText" && text($0) == want }), let f = frame(t),
                      let wf = frame(w) else { continue }
                let real = list.first { info in
                    guard info[kCGWindowOwnerPID as String] as? pid_t == pid, let b = info[kCGWindowBounds as String] as? NSDictionary,
                          let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
                    return abs(r.width - wf.width) < 1 && abs(r.minX - wf.minX) < 1
                }
                guard let b = real?[kCGWindowBounds as String] as? NSDictionary,
                      let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return f }
                // Top left of the window to the text: what moves with a stale frame is the
                // window's bottom, and SwiftUI lays out from the top.
                return f.offsetBy(dx: r.minX - wf.minX, dy: r.minY - wf.minY)
            }
            return nil
        }
        // The tree is there before the window is on screen: wait for both.
        func ours(at p: CGPoint) -> Bool {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let front = list.first { info in
                guard let b = info[kCGWindowBounds as String] as? NSDictionary,
                      let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
                return r.contains(p) && (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
            }
            return front?[kCGWindowOwnerPID as String] as? pid_t == pid
        }
        var found = findNow()
        let t0 = now()
        while now() - t0 < 2, found.map({ !ours(at: CGPoint(x: $0.midX, y: $0.midY)) }) ?? true { spin(0.005); found = findNow() }
        guard let f = found else { print("no text \(want)"); exit(1) }
        if ProcessInfo.processInfo.environment["NN_LAB_SHOOT"] == "1" {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            for info in list where info[kCGWindowOwnerPID as String] as? pid_t == pid {
                print("   window \(info[kCGWindowBounds as String] ?? "?") layer \(info[kCGWindowLayer as String] ?? "?")")
            }
            print("   text at \(f)")
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-R\(Int(f.minX) - 80),\(Int(f.minY) - 40),420,200", "build/panel-lab/early.png"]
            try? p.run(); p.waitUntilExit()
        }
        exit(click(at: CGPoint(x: f.midX, y: f.midY), ifFrontIs: pid) ? 0 : 1)
    case "ui-rclick":
        // A right click on the text in our panel, only if our panel is in front there.
        let want = args.dropFirst(2).joined(separator: " ")
        guard let t = texts.first(where: { text($0) == want }), let f = frame(t) else { print("no text \(want)"); exit(1) }
        let point = CGPoint(x: f.midX, y: f.midY)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let front = list.first { info in
            guard let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
            return r.contains(point) && (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
        }
        guard front?[kCGWindowOwnerPID as String] as? pid_t == pid else { print("  (not clicking: not ours in front)"); exit(1) }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .right)!.post(tap: .cghidEventTap)
        usleep(60_000)
        for type in [CGEventType.rightMouseDown, .rightMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right)!.post(tap: .cghidEventTap)
            usleep(60_000)
        }
    case "ui-close":
        // The ✕ of the row whose title is the text: over the row's top left corner, where
        // it shows on hover (hover the row first). For a heading, the ✕ at its right, level
        // with it.
        let want = args.dropFirst(2).joined(separator: " ")
        guard let t = texts.first(where: { text($0) == want }), let f = frame(t) else { print("no text \(want)"); exit(1) }
        let buttons = elements.filter { role($0) == "AXButton" }.compactMap { b in frame(b).map { (b, $0) } }
        let corner = buttons.filter { $0.1.width < 30 && $0.1.maxX < f.minX && f.minY - $0.1.minY < 30 && f.minY - $0.1.minY > -4 }
        let level = buttons.filter { $0.1.width < 30 && abs($0.1.midY - f.midY) < 8 && $0.1.minX > f.maxX }
        guard let b = corner.min(by: { $0.1.minX > $1.1.minX }) ?? level.max(by: { $0.1.minX < $1.1.minX })
        else { print("no close button by \(want)"); exit(1) }
        exit(click(at: CGPoint(x: b.1.midX, y: b.1.midY), ifFrontIs: pid) ? 0 : 1)
    default: // ui-button
        let want = args.dropFirst(2).joined(separator: " ")
        let match = elements.first { role($0) == "AXButton" && text($0) == want }
            ?? texts.first { text($0) == want }
        guard let m = match, let f = frame(m) else { print("no button \(want)"); exit(1) }
        exit(click(at: CGPoint(x: f.midX, y: f.midY), ifFrontIs: pid) ? 0 : 1)
    }

default:
    print("usage: lab uuid | flash native|react|prepark | tap | skin | actions | host")
    exit(64)
}
