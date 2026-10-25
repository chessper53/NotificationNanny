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

case "shut":
    // Closes the panel only if it is open; a clock press on a closed one opens it.
    if isOpen() { _ = pressClock(); _ = waitFor(3) { !isOpen() } }
    print("panel \(isOpen() ? "still open" : "closed")")

case "clock":
    exit(pressClock() ? 0 : 1)

// The ui-* commands drive NotificationNanny's own panel (pid as the second argument)
// through its accessibility tree, with real clicks.
case "ui-state", "ui-click", "ui-close", "ui-button", "ui-winid", "ui-scroll", "ui-count", "ui-widget":
    guard args.count >= 2, let pid = pid_t(args[1]) else { print("usage: lab \(args[0]) <pid> [text]"); exit(64) }
    let nn = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(nn, 2)
    let nnWindows = attr(nn, kAXWindowsAttribute) as? [AXUIElement] ?? []
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
        guard let id = mine.first?[kCGWindowNumber as String] as? Int else { print("none"); exit(1) }
        print(id)
    case "ui-state":
        let panelFrame = nnWindows.compactMap(frame).max { $0.height < $1.height }
        print("our panel: \(panelFrame.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? "none")")
        print("our texts: \(texts.map(text).filter { !$0.isEmpty }.joined(separator: " | "))")
        print("our buttons: \(elements.filter { role($0) == "AXButton" }.map(text).joined(separator: " | "))")
        print("NC panel open: \(isOpen()), NC window y: \(host().flatMap(frame).map { "\(Int($0.minY))" } ?? "none")")
        print("NC Lab rows: \(labRows().map { "\(str($0, kAXSubroleAttribute)?.replacingOccurrences(of: "AXNotificationCenter", with: "") ?? "?"):\(label($0).split(separator: ",").dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "?")" }.joined(separator: " | "))")
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
        let want = args.dropFirst(2).joined(separator: " ")
        guard let t = texts.first(where: { text($0) == want }), let f = frame(t) else { print("no text \(want)"); exit(1) }
        exit(click(at: CGPoint(x: f.midX, y: f.midY), ifFrontIs: pid) ? 0 : 1)
    case "ui-close":
        // The ✕ on the row whose title is the text: the rightmost button level with it.
        let want = args.dropFirst(2).joined(separator: " ")
        guard let t = texts.first(where: { text($0) == want }), let f = frame(t) else { print("no text \(want)"); exit(1) }
        let buttons = elements.filter { role($0) == "AXButton" }.compactMap { b in frame(b).map { (b, $0) } }
            .filter { abs($0.1.midY - f.midY) < 30 && $0.1.minX > f.maxX }
        guard let b = buttons.max(by: { $0.1.minX < $1.1.minX }) else { print("no close button by \(want)"); exit(1) }
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
