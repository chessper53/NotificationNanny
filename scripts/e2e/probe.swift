// External observations only: this helper never imports NotificationNannyCore.
import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 24 else { return [] }
    let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [element] + children.flatMap { descendants($0, depth: depth + 1) }
}

func text(_ element: AXUIElement) -> String {
    for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        if let value = attribute(element, key) as? String, !value.isEmpty { return value }
    }
    return ""
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
          AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: origin, size: size)
}

func rect(_ frame: CGRect) -> [String: Double] {
    ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
}

func emit(_ value: Any) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func windows(_ pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    return attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
}

func visibleFrames(_ pid: pid_t) -> [CGRect] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
}

func bannerDescription(_ element: AXUIElement) -> String {
    guard let value = attribute(element, "AXAttributedDescription") else { return "" }
    if CFGetTypeID(value) == CFAttributedStringGetTypeID() {
        return CFAttributedStringGetString((value as! CFAttributedString)) as String
    }
    return value as? String ?? ""
}

func press(pid: pid_t, title: String, button: String) -> Bool {
    let originalPointer = CGEvent(source: nil)?.location
    defer {
        if let point = originalPointer {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    repeat {
        for window in windows(pid) {
            let elements = descendants(window)
            guard elements.contains(where: { text($0) == title }), let bounds = frame(window) else { continue }
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: CGPoint(x: bounds.midX, y: bounds.midY), mouseButton: .left)?.post(tap: .cghidEventTap)
            if let target = elements.first(where: {
                attribute($0, kAXRoleAttribute) as? String == "AXButton" && text($0) == button
            }), AXUIElementPerformAction(target, kAXPressAction as CFString) == .success { return true }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while ProcessInfo.processInfo.systemUptime < deadline
    return false
}

let args = Array(CommandLine.arguments.dropFirst())
let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
let screens: [[String: Any]] = NSScreen.screens.compactMap { screen in
    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
          let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
    let v = screen.visibleFrame
    return ["uuid": CFUUIDCreateString(nil, uuid)! as String, "id": id,
            "visible": rect(CGRect(x: v.minX, y: primaryHeight - v.maxY, width: v.width, height: v.height))]
}

if args == ["status"] {
    emit(["trusted": AXIsProcessTrusted(), "locked": locked, "notificationCenter": nc != nil,
          "screens": screens,
          "runningApps": NSRunningApplication.runningApplications(withBundleIdentifier: "com.notificationnanny.app").map {
              ["pid": $0.processIdentifier, "path": $0.bundleURL?.path ?? ""] as [String: Any]
          }] as [String: Any])
    exit(0)
}
// Ask only the runner's own app to quit normally, so its delegate flushes
// preferences and restores Notification Center's parked window before exit.
if args.count == 2, args[0] == "quit", let pid = pid_t(args[1]),
   let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "com.notificationnanny.app" {
    exit(app.terminate() ? 0 : 1)
}
guard AXIsProcessTrusted(), !locked, let nc else {
    FileHandle.standardError.write(Data("Requires Accessibility permission, an unlocked desktop, and Notification Center.\n".utf8))
    exit(69)
}
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
if args.count == 4, args[0] == "press", let pid = pid_t(args[1]) {
    exit(press(pid: pid, title: args[2], button: args[3]) ? 0 : 1)
}
guard args.count == 3, args[0] == "snapshot", let pid = pid_t(args[1]) else {
    FileHandle.standardError.write(Data("usage: probe status | snapshot <pid> <run-token> | press <pid> <title> <button>\n".utf8))
    exit(64)
}
let token = args[2]
let subroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterBannerStack",
                              "AXNotificationCenterAlert", "AXNotificationCenterAlertStack"]
var native: [[String: Any]] = []
for window in windows(nc.processIdentifier) {
    for element in descendants(window) where subroles.contains(attribute(element, kAXSubroleAttribute) as? String ?? "") {
        let description = bannerDescription(element)
        guard description.hasPrefix("Lab "), description.contains(token), let bounds = frame(element) else { continue }
        native.append(["description": description, "frame": rect(bounds)])
    }
}
var overlays: [[String: Any]] = []
let onScreen = visibleFrames(pid)
for window in windows(pid) {
    let elements = descendants(window)
    let texts = elements.filter { attribute($0, kAXRoleAttribute) as? String == "AXStaticText" }.map(text)
    guard texts.contains(where: { $0.contains(token) }), let bounds = frame(window),
          onScreen.contains(where: { abs($0.minX - bounds.minX) < 2 && abs($0.minY - bounds.minY) < 2
              && abs($0.width - bounds.width) < 2 && abs($0.height - bounds.height) < 2 }) else { continue }
    overlays.append(["texts": texts, "frame": rect(bounds)])
}
emit(["native": native, "overlays": overlays, "screens": screens])
