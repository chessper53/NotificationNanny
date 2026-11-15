// Physically click only a verified menu bar clock; never act on notification content.
// Usage: clock-stress <cycles> [open-seconds] [closed-seconds]
import AppKit
import ApplicationServices

let args = Array(CommandLine.arguments.dropFirst())
let cycles = args.first.flatMap(Int.init) ?? 10
let openTime = args.dropFirst().first.flatMap(Double.init) ?? 0.65
let closedTime = args.dropFirst(2).first.flatMap(Double.init) ?? 0.65
guard cycles > 0, openTime >= 0.1, closedTime >= 0.1, AXIsProcessTrusted(),
      let screen = NSScreen.screens.first,
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
let nanny = NSRunningApplication.runningApplications(withBundleIdentifier: "com.notificationnanny.app").first
func customPanelVisible() -> Bool {
    guard let nanny else { return false }
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
        guard window[kCGWindowOwnerPID as String] as? pid_t == nanny.processIdentifier,
              window[kCGWindowLayer as String] as? Int == NSWindow.Level.statusBar.rawValue,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        return frame.width > 250 && frame.height > 60 && frame.intersects(CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height))
    }
}
var clock: CGPoint?
for x in stride(from: Int(screen.frame.maxX) - 25, through: Int(screen.frame.maxX) - 400, by: -6) {
    var element: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(x), 12, &element) == .success, let element else { continue }
    var identifier: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
    if identifier as? String == "com.apple.menuextra.clock" { clock = CGPoint(x: x, y: 12); break }
}
guard let clock else { fputs("Menu bar clock not found.\n", stderr); exit(1) }
let pointer = CGEvent(source: nil)?.location
let start = ProcessInfo.processInfo.systemUptime
func click(_ label: String) {
    print(String(format: "%.6f %@", ProcessInfo.processInfo.systemUptime - start, label))
    fflush(stdout)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: clock, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(30_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: clock, mouseButton: .left)?.post(tap: .cghidEventTap)
    if let pointer { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pointer, mouseButton: .left)?.post(tap: .cghidEventTap) }
}
func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
var failures = 0
for cycle in 1...cycles {
    click("open \(cycle)")
    spin(openTime)
    if openTime >= 0.6 {
        let nativeOpen = expanded(), customVisible = customPanelVisible()
        print("observed open=\(nativeOpen) customVisible=\(customVisible) at cycle \(cycle)")
        if !nativeOpen || !customVisible { failures += 1 }
        fflush(stdout)
    }
    click("close \(cycle)")
    spin(closedTime)
    if closedTime >= 0.6 {
        let closed = !expanded()
        print("observed closed=\(closed) at cycle \(cycle)")
        if !closed { failures += 1 }
        fflush(stdout)
    }
}
spin(1)
// Finish closed even if a rapid pair was coalesced by the system.
if expanded() { click("cleanup"); spin(1) }
print("finished closed=\(!expanded())")
exit(failures == 0 && !expanded() ? 0 : 1)
