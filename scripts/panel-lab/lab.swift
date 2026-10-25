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
func host() -> AXUIElement? { windows().max { (frame($0)?.width ?? 0) < (frame($1)?.width ?? 0) } }
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

case "clock":
    exit(pressClock() ? 0 : 1)

// The ui-* commands drive NotificationNanny's own panel (pid as the second argument)
// through its accessibility tree, with real clicks.
case "ui-state", "ui-click", "ui-close", "ui-button", "ui-winid", "ui-scroll":
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
