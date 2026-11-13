// Sample native and custom banner geometry every 50 ms, counting persistent placement failures.
// Requires Accessibility; commands and verdicts are in docs/LABS.md.

import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success ? v : nil
}
func rect(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterBannerStack",
                                   "AXNotificationCenterAlert", "AXNotificationCenterAlertStack"]
func banners(in e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 9 else { return [] }
    if let sub = attr(e, kAXSubroleAttribute) as? String, bannerSubroles.contains(sub) { return [e] }
    return (attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { banners(in: $0, depth: depth + 1) }
}
func label(_ e: AXUIElement) -> String {
    guard let d = attr(e, "AXAttributedDescription") else { return "?" }
    let s: String
    if CFGetTypeID(d) == CFAttributedStringGetTypeID() {
        s = CFAttributedStringGetString((d as! CFAttributedString)) as String
    } else {
        s = "\(d)"
    }
    // "App, Title, Body": keep app and title.
    return s.components(separatedBy: ", ").prefix(2).joined(separator: ", ")
}
func r(_ c: CGRect) -> String { "(\(Int(c.minX)),\(Int(c.minY)) \(Int(c.width))x\(Int(c.height)))" }

/// Screens' visible frames in AX coordinates (top left of the primary, y down).
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
let visibleFrames: [CGRect] = NSScreen.screens.map {
    let v = $0.visibleFrame
    return CGRect(x: v.minX, y: primaryHeight - v.maxY, width: v.width, height: v.height)
}
func onAnyScreen(_ c: CGRect) -> Bool {
    NSScreen.screens.contains {
        let f = $0.frame
        return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height).intersects(c)
    }
}
func fullyVisible(_ c: CGRect) -> Bool {
    visibleFrames.contains { $0.insetBy(dx: -1, dy: -1).contains(c) }
}

let args = CommandLine.arguments.dropFirst()

// Locked screens queue notifications without banners, so live measurements are invalid.
if args.first == "--locked" {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    exit((session["CGSSessionScreenIsLocked"] as? Bool ?? false) ? 0 : 1)
}

// Count every process window, including hidden ones, to detect leaked overlay panels.
if args.first == "--windows", let pid = args.dropFirst().first.flatMap({ Int32($0) }) {
    let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    print(all.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }.count)
    exit(0)
}

// Report stable display keys used by saved placements.
if args.first == "--screens" {
    for s in NSScreen.screens {
        guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() else { continue }
        print("\(CFUUIDCreateString(nil, uuid)!) \(Int(s.frame.width))x\(Int(s.frame.height)) \(n)")
    }
    exit(0)
}

guard AXIsProcessTrusted(),
      let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
else { print("needs Accessibility, and Notification Center running"); exit(99) }
let ncApp = AXUIElementCreateApplication(nc.processIdentifier)

// On macOS 27 the clock belongs to MenuBarAgent; press only the hit tested clock element.
if args.first == "--clock" {
    let system = AXUIElementCreateSystemWide()
    let right = Int(NSScreen.screens.first?.frame.maxX ?? 1700)
    for x in stride(from: right - 1, through: right - 400, by: -6) {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(x), 12, &el) == .success, let el,
              attr(el, kAXIdentifierAttribute) as? String == "com.apple.menuextra.clock" else { continue }
        exit(AXUIElementPerformAction(el, kAXPressAction as CFString) == .success ? 0 : 1)
    }
    print("menu bar clock not found")
    exit(1)
}

// Real clock clicks select a display; AX presses always open the main display. Restore the pointer
// afterwards.
if args.first == "--click-clock", let n = args.dropFirst().first.flatMap({ Int($0) }),
   n >= 1, n <= NSScreen.screens.count {
    let screen = NSScreen.screens[n - 1]
    let primaryTop = NSScreen.screens[0].frame.maxY
    let top = primaryTop - screen.frame.maxY
    let system = AXUIElementCreateSystemWide()
    for x in stride(from: Int(screen.frame.maxX) - 1, through: Int(screen.frame.maxX) - 500, by: -6) {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(x), Float(top) + 12, &el) == .success, let el,
              attr(el, kAXIdentifierAttribute) as? String == "com.apple.menuextra.clock" else { continue }
        let point = CGPoint(x: CGFloat(x), y: top + 12)
        let back = CGEvent(source: nil)!.location
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
                .post(tap: .cghidEventTap)
            usleep(60_000)
        }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)!
            .post(tap: .cghidEventTap)
        exit(0)
    }
    print("no clock on screen \(n)")
    exit(1)
}

// Expand only Lab stacks; leave personal notifications untouched.
if args.first == "--expand" {
    let prefix = "Lab \(args.dropFirst().first ?? ""),"
    for w in (attr(ncApp, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
        for b in banners(in: w) where label(b).hasPrefix(prefix) {
            guard (attr(b, kAXSubroleAttribute) as? String)?.hasSuffix("Stack") == true else { continue }
            exit(AXUIElementPerformAction(b, kAXPressAction as CFString) == .success ? 0 : 1)
        }
    }
    print("no stack from \(prefix)")
    exit(1)
}

// Simulate wake only for apps started in lab mode.
if args.first == "--wake" {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.notificationnanny.lab.wake"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// Close only Lab notifications, including Persistent leftovers; never touch other apps'
// notifications.
if args.first == "--close-all" || args.first == "--close-app" {
    let prefix = args.first == "--close-app" ? "Lab \(args.dropFirst().first ?? "")," : "Lab "
    // Close and Clear All in every language Notification Center ships, as the app does.
    var closeNames: Set<String> = ["Close", "Clear All"]
    let table = URL(fileURLWithPath: "/System/Library/CoreServices/NotificationCenter.app/Contents/Resources/Localizable.loctable")
    if let data = try? Data(contentsOf: table),
       let langs = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
        for case let strings as [String: Any] in langs.values {
            for key in ["Close", "Clear All"] { if let s = strings[key] as? String { closeNames.insert(s) } }
        }
    }
    var closed = 0
    for w in (attr(ncApp, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
        for b in banners(in: w) where label(b).hasPrefix(prefix) {
            var names: CFArray?
            AXUIElementCopyActionNames(b, &names)
            // Several notifications from one app merge into a stack, which offers
            // Clear All instead of Close.
            if let close = (names as? [String])?.first(where: { action in
                   closeNames.contains { action.hasPrefix("Name:\($0)\n") } }),
               AXUIElementPerformAction(b, close as CFString) == .success { closed += 1 }
        }
    }
    print("closed \(closed) banner(s)")
    exit(0)
}

// Report Lab action names in Notification Center's language.
if args.first == "--actions" {
    for w in (attr(ncApp, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
        for b in banners(in: w) where label(b).hasPrefix("Lab ") {
            var names: CFArray?
            AXUIElementCopyActionNames(b, &names)
            let shown = (names as? [String] ?? []).map {
                $0.hasPrefix("Name:") ? String($0.dropFirst(5).prefix { $0 != "\n" }) : $0
            }
            print("\(label(b)) [\(attr(b, kAXSubroleAttribute) as? String ?? "?")]: \(shown.joined(separator: " | "))")
        }
    }
    exit(0)
}

let seconds = Double(args.first ?? "10") ?? 10
let quiet = args.contains("--quiet")

struct Item { let kind: String; let name: String; let frame: CGRect }

var offscreen: [String] = []
var overlaps: [String] = []
// Require persistent errors; samples during native entrance animations can temporarily overlap or
// leave the screen.
var outFor: [String: Double] = [:], overlapFor: [String: Double] = [:]
let persist = 0.6
// Allow extra settling time for native slides under load before counting an offscreen failure.
let persistOffscreen = 1.0
var swallowedFor: Double = 0, worstSwallow: Double = 0
var hiddenFor: Double = 0, worstHidden: Double = 0, worstHiddenCount = 0
var lastSig = ""
let start = Date()
var lastTick = start

while Date().timeIntervalSince(start) < seconds {
    let now = Date()
    let t = now.timeIntervalSince(start)
    let dt = now.timeIntervalSince(lastTick); lastTick = now

    var present: [Item] = []
    for w in (attr(ncApp, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
        for b in banners(in: w) {
            if let f = rect(b) { present.append(Item(kind: "native", name: label(b), frame: f)) }
        }
    }
    // Measure overlay cards without the transparent close button margin.
    var overlays: [Item] = []
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in info where (w[kCGWindowOwnerName as String] as? String) == "NotificationNanny"
                     && ((w[kCGWindowLayer as String] as? Int) ?? 0) > 0 {
        guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let f = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        guard f.width < 900, f.height < 400, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { continue }
        // CustomBannerView.Metrics.chromeInset (8) at scale 1.
        overlays.append(Item(kind: "overlay", name: "panel", frame: f.insetBy(dx: 8, dy: 8)))
    }

    let visible = present.filter { onAnyScreen($0.frame) } + overlays
    if !present.isEmpty && visible.isEmpty { swallowedFor += dt } else { swallowedFor = 0 }
    worstSwallow = max(worstSwallow, swallowedFor)
    // Count native banners with no visible native or custom counterpart.
    let missing = present.count - visible.count
    if missing > 0 { hiddenFor += dt } else { hiddenFor = 0 }
    if hiddenFor > worstHidden { worstHidden = hiddenFor; worstHiddenCount = missing }

    let ids = visible.enumerated().map { "\($0.element.kind) \($0.element.kind == "overlay" ? "#\($0.offset)" : $0.element.name)" }
    var seenOut = Set<String>(), seenOverlap = Set<String>()
    for (v, id) in zip(visible, ids) where !fullyVisible(v.frame) {
        seenOut.insert(id)
        outFor[id, default: 0] += dt
        let msg = "\(id) at \(r(v.frame))"
        if outFor[id]! >= persistOffscreen, !offscreen.contains(where: { $0.hasPrefix(id + " at") }) { offscreen.append(msg) }
    }
    for i in visible.indices {
        for j in visible.indices where j > i
            && visible[i].frame.insetBy(dx: 2, dy: 2).intersects(visible[j].frame.insetBy(dx: 2, dy: 2)) {
            let key = "\(ids[i]) × \(ids[j])"
            seenOverlap.insert(key)
            overlapFor[key, default: 0] += dt
            if overlapFor[key]! >= persist, !overlaps.contains(where: { $0.hasPrefix(key) }) {
                overlaps.append("\(key) \(r(visible[i].frame)) \(r(visible[j].frame))")
            }
        }
    }
    outFor = outFor.filter { seenOut.contains($0.key) }
    overlapFor = overlapFor.filter { seenOverlap.contains($0.key) }

    let lines = present.map { "  \(onAnyScreen($0.frame) ? "native " : "parked ") \(r($0.frame)) \($0.name)" }
              + overlays.map { "  overlay \(r($0.frame))" }
    let sig = lines.joined(separator: "\n")
    if sig != lastSig, !quiet {
        lastSig = sig
        print(String(format: "t=%5.2fs", t) + (lines.isEmpty ? "  (nothing)" : ""))
        lines.forEach { print($0) }
    }
    Thread.sleep(forTimeInterval: 0.05)
}

var failures = 0
print("\n== checks ==")
if offscreen.isEmpty { print("ok    offscreen: nothing visible outside a screen") }
else { failures += 1; print("FAIL  offscreen:"); offscreen.prefix(8).forEach { print("        \($0)") } }
if worstSwallow <= 1.5 { print("ok    swallowed: longest gap with banners but nothing visible \(String(format: "%.2f", worstSwallow))s") }
else { failures += 1; print("FAIL  swallowed: banners present but nothing visible for \(String(format: "%.2f", worstSwallow))s") }
if worstHidden <= 1.5 { print("ok    hidden: every banner visible natively or as an overlay") }
else { failures += 1; print("FAIL  hidden: \(worstHiddenCount) banner(s) not shown for \(String(format: "%.2f", worstHidden))s") }
if overlaps.isEmpty { print("ok    overlap: none") }
else { failures += 1; print("FAIL  overlap:"); overlaps.prefix(8).forEach { print("        \($0)") } }
exit(Int32(failures))
