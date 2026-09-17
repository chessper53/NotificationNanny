#!/usr/bin/env swift
// Dumps the Notification Center accessibility tree and tests the one assumption
// NotificationNanny's repositioning depends on.
//
// Since macOS 26, banners are not separate windows. They are SwiftUI views
// inside a single fullscreen host window (AXWindow/AXSystemDialog containing an
// AXHostingView). The banner's own AX position is read-only, so the app cannot
// move the banner directly. What it does instead is move the *host window* so
// the banner child lands where the user asked. That works only while the host
// window's AXPosition is settable and the value it is given actually sticks.
//
// This probe reports whether that is still true. Run it while a banner is on
// screen; it posts one itself.
//
//   swift scripts/ax-probe.swift
//
// The process running it needs Accessibility permission (System Settings >
// Privacy & Security > Accessibility). If you run it from Terminal, grant it to
// Terminal. Quit NotificationNanny first, otherwise you will be measuring its
// repositioning rather than the system's behaviour.

import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success ? v : nil
}

func point(_ e: AXUIElement, _ key: String) -> CGPoint {
    guard let v = attr(e, key) else { return .zero }
    var p = CGPoint.zero
    AXValueGetValue(v as! AXValue, .cgPoint, &p)
    return p
}

func size(_ e: AXUIElement, _ key: String) -> CGSize {
    guard let v = attr(e, key) else { return .zero }
    var s = CGSize.zero
    AXValueGetValue(v as! AXValue, .cgSize, &s)
    return s
}

func settable(_ e: AXUIElement, _ key: String) -> Bool {
    var b: DarwinBoolean = false
    AXUIElementIsAttributeSettable(e, key as CFString, &b)
    return b.boolValue
}

func dump(_ e: AXUIElement, depth: Int, maxDepth: Int) {
    guard depth <= maxDepth else { return }
    let role = attr(e, kAXRoleAttribute as String) as? String ?? "?"
    let sub  = attr(e, kAXSubroleAttribute as String) as? String ?? ""
    let desc = attr(e, kAXDescriptionAttribute as String) as? String ?? ""
    let p = point(e, kAXPositionAttribute as String)
    let s = size(e, kAXSizeAttribute as String)
    let pad = String(repeating: "  ", count: depth)
    print("\(pad)\(role)\(sub.isEmpty ? "" : "/\(sub)") "
        + "pos=(\(Int(p.x)),\(Int(p.y))) size=\(Int(s.width))x\(Int(s.height)) "
        + "posSettable=\(settable(e, kAXPositionAttribute as String))"
        + (desc.isEmpty ? "" : " \"\(desc.prefix(48))\""))
    let kids = attr(e, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    for k in kids.prefix(8) { dump(k, depth: depth + 1, maxDepth: maxDepth) }
}

let os = ProcessInfo.processInfo.operatingSystemVersion
print("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
print("probe is AX-trusted: \(AXIsProcessTrusted())")
guard AXIsProcessTrusted() else {
    print("\nGrant Accessibility to whichever app is running this, then re-run.")
    exit(1)
}

if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.notificationnanny.app").isEmpty {
    print("\nNOTE: NotificationNanny is running. Quit it first or the numbers below")
    print("      reflect its repositioning, not the system's own behaviour.")
}

guard let nc = NSRunningApplication
    .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
    print("Notification Center is not running."); exit(1)
}
print("NotificationCenter pid \(nc.processIdentifier)")

// Give ourselves something to look at.
let task = Process()
task.launchPath = "/usr/bin/osascript"
task.arguments = ["-e", "display notification \"AX probe\" with title \"NotificationNanny probe\""]
try? task.run()
task.waitUntilExit()
Thread.sleep(forTimeInterval: 1.8)

let app = AXUIElementCreateApplication(nc.processIdentifier)
let windows = attr(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
print("\n=== window tree (\(windows.count) window(s)) ===")
for w in windows { dump(w, depth: 0, maxDepth: 3) }

print("\n=== can the host window be moved, and does it stay moved? ===")
var testedAny = false
for w in windows {
    let s = size(w, kAXSizeAttribute as String)
    // The fullscreen banner host, as opposed to small widget windows.
    guard s.width > 700 || s.height > 400 else { continue }
    testedAny = true
    let before = point(w, kAXPositionAttribute as String)
    let canSet = settable(w, kAXPositionAttribute as String)
    var target = CGPoint(x: before.x - 250, y: before.y + 100)
    guard let value = AXValueCreate(.cgPoint, &target) else { continue }
    let err = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, value)
    Thread.sleep(forTimeInterval: 0.3)
    let immediately = point(w, kAXPositionAttribute as String)
    // The failure the 26.6.2 reports describe is the layout engine putting it
    // back, which a single read right after the write would miss.
    Thread.sleep(forTimeInterval: 1.2)
    let afterSettling = point(w, kAXPositionAttribute as String)

    print("host \(Int(s.width))x\(Int(s.height)): posSettable=\(canSet) setError=\(err.rawValue)")
    print("  requested      (\(Int(target.x)),\(Int(target.y)))")
    print("  read back      (\(Int(immediately.x)),\(Int(immediately.y)))   applied=\(immediately == target)")
    print("  after 1.2s     (\(Int(afterSettling.x)),\(Int(afterSettling.y)))   held=\(afterSettling == target)")
    if immediately == target && afterSettling != target {
        print("  >> REVERTED: the write lands, then something puts it back.")
    } else if immediately != target {
        print("  >> REJECTED: the write does not take effect at all.")
    } else {
        print("  >> OK: repositioning works on this system.")
    }

    var restore = before
    if let v = AXValueCreate(.cgPoint, &restore) {
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
    }
}
if !testedAny {
    print("No fullscreen host window found. Either no banner was on screen, or the")
    print("hierarchy changed shape again; the tree above is the useful part.")
}

// The decisive question. NotificationNanny repositions when it sees
// AXWindowCreated. If the fullscreen host is torn down between banners that
// fires every time and all is well; if the host persists, the only signal a
// banner arrived is AXLayoutChanged, which older builds do not subscribe to,
// and the banner is never moved.
print("\n=== which events does a banner actually emit? ===")

let watched = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
               kAXWindowMovedNotification, kAXMainWindowChangedNotification,
               kAXUIElementDestroyedNotification, kAXLayoutChangedNotification,
               kAXCreatedNotification, kAXResizedNotification] as [String]

var counts: [String: Int] = [:]
let callback: AXObserverCallback = { _, _, note, _ in
    counts[note as String, default: 0] += 1
}
var observer: AXObserver?
AXObserverCreate(nc.processIdentifier, callback, &observer)
if let observer {
    for n in watched { AXObserverAddNotification(observer, app, n as CFString, nil) }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)

    DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
        let t = Process()
        t.launchPath = "/usr/bin/osascript"
        t.arguments = ["-e", "display notification \"event probe\" with title \"NotificationNanny probe\""]
        try? t.run()
        t.waitUntilExit()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        for n in watched { print("  \(n): \(counts[n] ?? 0)") }
        let created = counts[kAXWindowCreatedNotification as String] ?? 0
        let layout  = counts[kAXLayoutChangedNotification as String] ?? 0
        print("")
        if created == 0 && layout > 0 {
            print(">> AXWindowCreated never fired; only AXLayoutChanged did.")
            print("   A build that listens only for window-created will never see the")
            print("   banner, which matches 'notifications stay in the top right'.")
        } else if created > 0 {
            print(">> AXWindowCreated fired, so the host is torn down between banners")
            print("   and the original mechanism still has a signal to work from.")
        } else {
            print(">> No events at all. Check that a banner really appeared, and that")
            print("   Do Not Disturb is off.")
        }
        exit(0)
    }
    CFRunLoopRun()
}
