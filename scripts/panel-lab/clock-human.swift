// Human-like clock driver: random waits (including long idle before opening), clicks at
// varied points inside the verified clock, and closes by clock, Escape or a click on empty
// menu bar space. Never clicks notification content. Prints absolute uptime per action.
// Usage: clock-human <openings> [seed] [quick]  (quick: always close by clock, reopen after 0.15-0.4 s)
import AppKit
import ApplicationServices

let args = Array(CommandLine.arguments.dropFirst())
let openings = args.first.flatMap(Int.init) ?? 10
var rng = SystemRandomNumberGenerator()
var seeded = args.dropFirst().first.flatMap(UInt64.init)
let quick = args.count > 2 && args[2] == "quick"
func random(_ range: ClosedRange<Double>) -> Double {
    guard var s = seeded else { return Double.random(in: range, using: &rng) }
    s = s &* 6364136223846793005 &+ 1442695040888963407; seeded = s
    return range.lowerBound + Double(s >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
}
guard AXIsProcessTrusted(), let screen = NSScreen.screens.first,
      let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
else { fputs("Needs Accessibility, a display and Notification Center.\n", stderr); exit(1) }
let app = AXUIElementCreateApplication(nc.processIdentifier)
AXUIElementSetMessagingTimeout(app, 0.3)
func expanded() -> Bool {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(app, "AXExpanded" as CFString, &value) == .success && value as? Bool == true
}
guard !expanded() else { fputs("Close Notification Center before starting.\n", stderr); exit(1) }
let system = AXUIElementCreateSystemWide()
func element(at x: Double, _ y: Double) -> AXUIElement? {
    var element: AXUIElement?
    return AXUIElementCopyElementAtPosition(system, Float(x), Float(y), &element) == .success ? element : nil
}
func string(_ e: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(e, attribute as CFString, &value)
    return value as? String
}
func clockRect() -> CGRect? {
    for x in stride(from: Double(screen.frame.maxX) - 25, through: Double(screen.frame.maxX) - 400, by: -6) {
        guard let e = element(at: x, 12), string(e, kAXIdentifierAttribute) == "com.apple.menuextra.clock" else { continue }
        var p: CFTypeRef?, s: CFTypeRef?
        AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p)
        AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &s)
        var origin = CGPoint.zero, size = CGSize.zero
        guard let p, let s, AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
    return nil
}
// Empty menu bar space: the menu bar itself, not an item, an app menu or a status item.
var emptyBar: CGPoint?
for x in stride(from: Double(screen.frame.midX), through: Double(screen.frame.maxX) - 600, by: 40) {
    if let e = element(at: x, 12), string(e, kAXRoleAttribute) == "AXMenuBar" { emptyBar = CGPoint(x: x, y: 12); break }
}
let pointer = CGEvent(source: nil)?.location
func log(_ s: String) { print(String(format: "%.3f %@", ProcessInfo.processInfo.systemUptime, s)); fflush(stdout) }
/// Glide there like a hand does, so hover-driven behavior sees the approach.
func glide(to point: CGPoint) {
    let from = CGEvent(source: nil)?.location ?? point
    let steps = 12, duration = random(0.15...0.35)
    for step in 1...steps {
        let f = Double(step) / Double(steps), eased = 1 - (1 - f) * (1 - f)
        let p = CGPoint(x: from.x + (point.x - from.x) * eased, y: from.y + (point.y - from.y) * eased)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(useconds_t(duration / Double(steps) * 1e6))
    }
}
func click(_ point: CGPoint, hold: Double) {
    glide(to: point)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(useconds_t(hold * 1e6))
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func clickClock(_ label: String) {
    guard let r = clockRect() else { log("clock not found"); return }
    // Like a person: often the clock, sometimes flung into the corner or onto the top edge.
    let roll = random(0...1)
    let point = roll < 0.25 ? CGPoint(x: Double(screen.frame.maxX) - random(0.5...20), y: random(0...3))
        : roll < 0.4 ? CGPoint(x: r.minX - random(0...3), y: random(0...1) < 0.5 ? random(0...3) : r.midY)
        : CGPoint(x: r.minX + 3 + random(0...1) * (r.width - 6), y: r.minY + 4 + random(0...1) * (r.height - 8))
    let hold = random(0.04...0.18)
    log(String(format: "%@ clock x+%.0f hold %.0f ms", label, point.x - r.minX, hold * 1000))
    click(point, hold: hold)
}
func escape() {
    log("close escape")
    for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap); usleep(40_000) }
}
func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

for opening in 1...openings {
    // Mostly human pauses, sometimes long idle, sometimes an immediate reopen.
    let roll = random(0...1)
    let closed = quick ? random(0.15...0.4) : roll < 0.2 ? random(4...12) : roll < 0.35 ? random(0.15...0.5) : random(0.6...3)
    log(String(format: "wait %.2f s closed", closed))
    if closed > 2, let pointer { glide(to: pointer) }
    spin(closed)
    clickClock("open \(opening)")
    let open = quick ? random(0.9...1.6) : random(0...1) < 0.2 ? random(0.25...0.6) : random(0.8...3)
    spin(open)
    let how = random(0...1)
    if quick || how < 0.6 || emptyBar == nil { clickClock("close \(opening)") }
    else if how < 0.8 { escape() }
    else { log("close empty-bar"); click(emptyBar!, hold: random(0.04...0.12)) }
}
spin(1.5)
if expanded() { clickClock("cleanup"); spin(1.5) }
if let pointer { glide(to: pointer) }
log("finished closed=\(!expanded())")
