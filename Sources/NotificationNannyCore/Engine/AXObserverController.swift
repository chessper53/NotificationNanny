import AppKit
@preconcurrency import ApplicationServices

/// Owns AXObserver attach/detach lifecycle and NC-process discovery — the "am I watching the
/// right process, and is the C callback wired up" concern, isolated from
/// `NotificationRepositioner`'s banner-decision and reposition-state logic. Delivers every raw
/// AX event to a single `onEvent` closure; the repositioner decides what to do with each one.
@MainActor
final class AXObserverController {
    private(set) var isObserving = false
    private(set) var ncApp: AXUIElement?
    private(set) var ncPid: pid_t = 0

    private var observer: AXObserver?
    private var onEvent: ((AXUIElement, String) -> Void)?

    private static let watchedNotifications: [String] = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
        kAXWindowMovedNotification, kAXMainWindowChangedNotification,
        kAXUIElementDestroyedNotification,
    ]

    deinit {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    /// Attaches to the NC process and starts delivering AX events to `onEvent`. Returns false
    /// if the NC process couldn't be found (caller should retry once it launches).
    @discardableResult
    func start(onEvent: @escaping (AXUIElement, String) -> Void) -> Bool {
        stop()
        self.onEvent = onEvent

        let pid = Self.findNotificationProcessPid()
        guard pid > 0 else { return false }
        let app = AXUIElementCreateApplication(pid)

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, axObserverControllerCallback, &newObserver) == .success,
              let newObserver else { return false }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.watchedNotifications {
            AXObserverAddNotification(newObserver, app, name as CFString, selfPtr)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)

        observer = newObserver
        ncApp = app
        ncPid = pid
        isObserving = true
        return true
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        ncApp = nil
        ncPid = 0
        isObserving = false
        onEvent = nil
    }

    fileprivate func deliver(element: AXUIElement, notification: String) {
        onEvent?(element, notification)
    }

    /// Finds the notification-center process: exact bundle ID match, then any running app whose
    /// bundle ID contains "notification", then a `CGWindowList` scan for a window owner whose
    /// name contains "notification". No subprocess spawned.
    private static func findNotificationProcessPid() -> pid_t {
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first {
            return app.processIdentifier
        }
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier?.localizedCaseInsensitiveContains("notification") == true {
                return app.processIdentifier
            }
        }
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  ownerName.localizedCaseInsensitiveContains("notification"),
                  let pid = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            return pid
        }
        return 0
    }
}

private func axObserverControllerCallback(observer: AXObserver, element: AXUIElement,
                                          notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let controller = Unmanaged<AXObserverController>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    Task { @MainActor in controller.deliver(element: element, notification: name) }
}
