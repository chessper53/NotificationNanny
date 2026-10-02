// Samples where banners actually are and checks them.
//
//   watch <seconds> [--quiet]
//
// Every 50 ms it reads the Notification Center banners (AX) and
// NotificationNanny's custom overlay panels (CGWindowList), prints a line
// whenever that picture changes, and at the end reports:
//
//   offscreen   a visible banner or overlay sticking out of its screen's visible frame
//   swallowed   banners exist but nothing has been visible for more than 1.5 s
//   overlap     two visible banners or overlays covering each other
//
// Exit status is the number of failed checks. Needs Accessibility for whatever
// runs it.

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

// `watch --screens`: display UUIDs, the keys NotificationNanny stores placements under.
if args.first == "--screens" {
    for s in NSScreen.screens {
        guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() else { continue }
        print("\(CFUUIDCreateString(nil, uuid)!) \(Int(s.frame.width))x\(Int(s.frame.height))")
    }
    exit(0)
}

guard AXIsProcessTrusted(),
      let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
else { print("needs Accessibility, and Notification Center running"); exit(99) }
let ncApp = AXUIElementCreateApplication(nc.processIdentifier)

// `watch --close-all`: closes every banner on screen, e.g. persistent leftovers.
if args.first == "--close-all" {
    var closed = 0
    for w in (attr(ncApp, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
        for b in banners(in: w) {
            var names: CFArray?
            AXUIElementCopyActionNames(b, &names)
            if let close = (names as? [String])?.first(where: { $0.hasPrefix("Name:Close") }),
               AXUIElementPerformAction(b, close as CFString) == .success { closed += 1 }
        }
    }
    print("closed \(closed) banner(s)")
    exit(0)
}

let seconds = Double(args.first ?? "10") ?? 10
let quiet = args.contains("--quiet")

struct Item { let kind: String; let name: String; let frame: CGRect }

var offscreen: [String] = []
var overlaps: [String] = []
// Seconds each problem has persisted. Transitions are animated, so a banner
// mid-slide pokes out for a few samples; only what stays wrong counts.
var outFor: [String: Double] = [:], overlapFor: [String: Double] = [:]
let persist = 0.6
var swallowedFor: Double = 0, worstSwallow: Double = 0
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
    // Overlay panels: NotificationNanny windows above normal level. The panel
    // carries a transparent margin for the close button, so shrink it to the
    // banner it draws.
    var overlays: [Item] = []
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in info where (w[kCGWindowOwnerName as String] as? String) == "NotificationNanny"
                     && ((w[kCGWindowLayer as String] as? Int) ?? 0) > 0 {
        guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let f = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        guard f.width < 900, f.height < 400, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { continue }
        overlays.append(Item(kind: "overlay", name: "panel", frame: f.insetBy(dx: 12, dy: 12)))
    }

    let visible = present.filter { onAnyScreen($0.frame) } + overlays
    if !present.isEmpty && visible.isEmpty { swallowedFor += dt } else { swallowedFor = 0 }
    worstSwallow = max(worstSwallow, swallowedFor)

    let ids = visible.enumerated().map { "\($0.element.kind) \($0.element.kind == "overlay" ? "#\($0.offset)" : $0.element.name)" }
    var seenOut = Set<String>(), seenOverlap = Set<String>()
    for (v, id) in zip(visible, ids) where !fullyVisible(v.frame) {
        seenOut.insert(id)
        outFor[id, default: 0] += dt
        let msg = "\(id) at \(r(v.frame))"
        if outFor[id]! >= persist, !offscreen.contains(where: { $0.hasPrefix(id + " at") }) { offscreen.append(msg) }
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
if overlaps.isEmpty { print("ok    overlap: none") }
else { failures += 1; print("FAIL  overlap:"); overlaps.prefix(8).forEach { print("        \($0)") } }
exit(Int32(failures))
