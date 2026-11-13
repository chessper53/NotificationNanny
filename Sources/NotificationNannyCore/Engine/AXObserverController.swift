import AppKit
@preconcurrency import ApplicationServices

/// Owns the Notification Center observer lifecycle and forwards AX events to `onEvent`.
@MainActor
final class AXObserverController {
    private(set) var isObserving = false
    private(set) var ncApp: AXUIElement?
    private(set) var ncPid: pid_t = 0

    private var observer: AXObserver?
    private var onEvent: ((AXUIElement, String) -> Void)?
    /// Why the last start failed, for the log; nil after one that worked.
    private(set) var lastStartFailure: String?

    /// Layout changes announce arrivals; destroyed elements end overlays and sounds. Both are
    /// required.
    private static let requiredNotifications: Set<String> = [
        kAXLayoutChangedNotification, kAXUIElementDestroyedNotification,
    ]

    /// From macOS 26, banners share a persistent host, so arrivals need layout events, not new
    /// windows.
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

    /// Starts delivering AX events; returns false if discovery, observer creation, or a required
    /// subscription fails.
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
        // Bound waits across all AX elements so an unresponsive Notification Center cannot stall
        // each call for six seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
        let app = AXUIElementCreateApplication(pid)

        var newObserver: AXObserver?
        let created = AXObserverCreate(pid, axObserverControllerCallback, &newObserver)
        guard created == .success, let newObserver else {
            lastStartFailure = "observer not created (\(created.rawValue))"
            return false
        }

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

    /// The current Notification Center PID, or 0 if absent; may differ from the observed PID after
    /// a restart.
    var currentProcessPid: pid_t { Self.findNotificationProcessPid() }

    fileprivate func deliver(element: AXUIElement, notification: String) {
        onEvent?(element, notification)
    }

    /// Finds Notification Center by bundle ID, then Apple app or window owner name. Excludes this
    /// app.
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
