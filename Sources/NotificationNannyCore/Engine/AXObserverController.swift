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
    /// Why the last start failed, for the log; nil after one that worked.
    private(set) var lastStartFailure: String?

    /// Without these, banners are never seen: layout changes are the only sign one arrived
    /// (see watchedNotifications), and destroyed elements end overlays and sounds. The rest
    /// help, and a start goes on without them.
    private static let requiredNotifications: Set<String> = [
        kAXLayoutChangedNotification, kAXUIElementDestroyedNotification,
    ]

    /// `kAXLayoutChangedNotification` matters from macOS 26 on. A banner is no longer its own
    /// window: it is a SwiftUI view added inside one persistent fullscreen `AXSystemDialog`
    /// host. Because that host is not torn down between banners, `kAXWindowCreatedNotification`
    /// never fires for a banner at all — measured as 0 on 27.0, against 3 layout-changed events
    /// per banner. Layout-changed is the only arrival signal, so without it a banner is only
    /// ever repositioned by accident, when some *other* element's destroy event happens to
    /// trigger a sweep.
    private static let watchedNotifications: [String] = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
        kAXWindowMovedNotification, kAXMainWindowChangedNotification,
        kAXUIElementDestroyedNotification, kAXLayoutChangedNotification,
    ]

    /// Seconds an AX call may wait. Healthy calls take milliseconds.
    static let messagingTimeout: Float = 1

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
        lastStartFailure = nil

        let pid = Self.findNotificationProcessPid()
        guard pid > 0 else {
            lastStartFailure = "Notification Center isn't running"
            return false
        }
        // Every call into Notification Center otherwise waits up to the system default of
        // six seconds. Right after a display wake NC was measured taking about fifteen
        // seconds to answer; at six seconds per call a sweep stalled the main thread and
        // banners stayed native meanwhile. Failing fast lets the next sweep catch up the
        // moment NC answers again. Set on the system-wide element, it covers every element.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
        let app = AXUIElementCreateApplication(pid)

        var newObserver: AXObserver?
        let created = AXObserverCreate(pid, axObserverControllerCallback, &newObserver)
        guard created == .success, let newObserver else {
            lastStartFailure = "observer not created (\(created.rawValue))"
            return false
        }

        // Its answers were ignored, and observing was reported whatever they were.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var failed: [String] = []
        for name in Self.watchedNotifications {
            let result = AXObserverAddNotification(newObserver, app, name as CFString, selfPtr)
            if result != .success, result != .notificationAlreadyRegistered { failed.append("\(name) (\(result.rawValue))") }
        }
        if failed.contains(where: { f in Self.requiredNotifications.contains { f.hasPrefix($0) } }) {
            for name in Self.watchedNotifications { AXObserverRemoveNotification(newObserver, app, name as CFString) }
            lastStartFailure = "Notification Center refused \(failed.joined(separator: ", "))"
            return false
        }
        if !failed.isEmpty {
            NannyLogger.shared.log("Observing without \(failed.joined(separator: ", "))", level: .warn, tag: "AX")
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

    /// The PID Notification Center runs under right now, or 0 if it isn't running. Differs from
    /// `ncPid` once NC has been relaunched under us, which macOS does across a long sleep.
    var currentProcessPid: pid_t { Self.findNotificationProcessPid() }

    fileprivate func deliver(element: AXUIElement, notification: String) {
        onEvent?(element, notification)
    }

    /// Finds the notification-center process: exact bundle ID match, then any running Apple app
    /// whose bundle ID contains "notification", then a `CGWindowList` scan for a window owner
    /// whose name contains "notification". No subprocess spawned. Never this app, whose bundle
    /// ID and name both contain "notification": attached to itself, it reported observing.
    private static func findNotificationProcessPid() -> pid_t {
        let ourPid = ProcessInfo.processInfo.processIdentifier
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first {
            return app.processIdentifier
        }
        for app in NSWorkspace.shared.runningApplications {
            if app.processIdentifier != ourPid, let id = app.bundleIdentifier, id.hasPrefix("com.apple."),
               id.localizedCaseInsensitiveContains("notification") {
                return app.processIdentifier
            }
        }
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  ownerName.localizedCaseInsensitiveContains("notification"),
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ourPid else { continue }
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
