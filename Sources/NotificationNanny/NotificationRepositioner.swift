import AppKit
import ApplicationServices
import Combine
import os

private let log = Logger(subsystem: "com.notificationnanny", category: "repositioner")

/// Watches `com.apple.notificationcenterui` for new windows and repositions them
/// to the user-selected location via the Accessibility API.
///
/// Apple does not expose a public API for moving notification banners. This is the
/// least-bad approach that does not require private SPI: subscribe to AX window
/// notifications on the NotificationCenter process and `kAXPositionAttribute`
/// each window as it appears.
@MainActor
final class NotificationRepositioner: ObservableObject {
    @Published private(set) var hasAccessibilityPermission: Bool = false
    @Published private(set) var isObserving: Bool = false

    private var settings: AppSettings?
    private var cancellables = Set<AnyCancellable>()

    private var observer: AXObserver?
    private var ncApp: AXUIElement?
    private var ncPid: pid_t = 0
    private var permissionPollTimer: Timer?

    init() {
        refreshAccessibilityStatus()
        // If the user grants permission via System Settings (without clicking
        // the in-app button), poll until we notice and start observing.
        startPermissionPollIfNeeded()
        // The NotificationCenterUI process can be relaunched; re-bind when it does.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.notificationcenterui" else { return }
            Task { @MainActor [weak self] in
                self?.startObserving()
            }
        }
    }

    func bind(to settings: AppSettings) {
        guard self.settings == nil else { return }
        self.settings = settings

        // Re-apply on every settings change. Throttle so dragging a slider doesn't
        // hammer the AX API at full screen-refresh rate.
        settings.objectWillChange
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.repositionVisibleWindows()
            }
            .store(in: &cancellables)

        startObserving()
    }

    // MARK: - Accessibility permission

    func refreshAccessibilityStatus() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        refreshAccessibilityStatus()
        startPermissionPollIfNeeded()
    }

    private func startPermissionPollIfNeeded() {
        guard permissionPollTimer == nil, !hasAccessibilityPermission else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshAccessibilityStatus()
                if self.hasAccessibilityPermission {
                    timer.invalidate()
                    self.permissionPollTimer = nil
                    self.startObserving()
                }
            }
        }
    }

    // MARK: - Observation

    func startObserving() {
        guard hasAccessibilityPermission else {
            log.warning("startObserving: no AX permission, polling")
            startPermissionPollIfNeeded()
            return
        }

        teardownObserver()

        let pid = findNotificationProcessPid()
        guard pid > 0 else {
            log.error("startObserving: could not find notification process")
            return
        }
        log.info("startObserving: attaching to pid \(pid)")
        let app = AXUIElementCreateApplication(pid)

        var newObserver: AXObserver?
        let createResult = AXObserverCreate(pid, axNotificationCallback, &newObserver)
        guard createResult == .success, let newObserver else {
            log.error("AXObserverCreate failed: \(createResult.rawValue)")
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let notes: [String] = [
            kAXWindowCreatedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXWindowMovedNotification as String,
            kAXMainWindowChangedNotification as String,
        ]
        for name in notes {
            let r = AXObserverAddNotification(newObserver, app, name as CFString, selfPtr)
            log.info("Subscribe \(name, privacy: .public): \(r.rawValue)")
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )

        self.observer = newObserver
        self.ncApp = app
        self.ncPid = pid
        self.isObserving = true

        log.info("Observer attached, listing current windows…")
        dumpWindows()
        repositionVisibleWindows()
    }

    /// Try the historical bundle id first; fall back to scanning the process
    /// list for `usernotificationsd` or anything else that handles banners on
    /// modern macOS.
    private func findNotificationProcessPid() -> pid_t {
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
            .first {
            log.info("Found NotificationCenter via bundle id, pid \(app.processIdentifier)")
            return app.processIdentifier
        }
        // Walk all running apps looking for anything notification-y.
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier else { continue }
            if bid.localizedCaseInsensitiveContains("notification") {
                log.info("Fallback: \(bid), pid \(app.processIdentifier)")
                return app.processIdentifier
            }
        }
        // Last resort: pgrep usernotificationsd via shell.
        return pgrepFirst(name: "usernotificationsd")
    }

    private func pgrepFirst(name: String) -> pid_t {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = [name]
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8),
               let line = str.split(separator: "\n").first,
               let pid = pid_t(line.trimmingCharacters(in: .whitespaces)) {
                log.info("pgrep \(name): pid \(pid)")
                return pid
            }
        } catch {
            log.error("pgrep failed: \(error.localizedDescription)")
        }
        return 0
    }

    private func dumpWindows() {
        guard let ncApp else { return }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            log.warning("dumpWindows: copy failed (\(result.rawValue))")
            return
        }
        log.info("dumpWindows: \(windows.count) window(s)")
        for (i, w) in windows.enumerated() {
            var sizeRef: CFTypeRef?
            var posRef: CFTypeRef?
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef)
            AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleRef)
            var size = CGSize.zero, pos = CGPoint.zero
            if let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
                AXValueGetValue(v as! AXValue, .cgSize, &size)
            }
            if let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
                AXValueGetValue(v as! AXValue, .cgPoint, &pos)
            }
            let title = (titleRef as? String) ?? ""
            log.info("  [\(i)] '\(title)' size=\(size.width)x\(size.height) pos=(\(pos.x),\(pos.y))")
        }
    }

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        ncApp = nil
        ncPid = 0
        isObserving = false
    }

    // MARK: - Repositioning

    fileprivate func handleAXEvent(element: AXUIElement, notification: String) {
        log.info("AX event: \(notification, privacy: .public)")
        // The event element may be the app or the window; try repositioning both.
        repositionWindow(element)
        repositionVisibleWindows()
    }

    private func repositionVisibleWindows() {
        guard let ncApp else { return }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return }
        for window in windows {
            repositionWindow(window)
        }
    }

    private func repositionWindow(_ window: AXUIElement) {
        guard let settings, settings.isEnabled else { return }

        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return }
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return }

        // Figure out which screen the notification currently lives on so we
        // reposition relative to the right display in a multi-monitor setup.
        var currentAxPoint = CGPoint.zero
        var posRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
           let posValue = posRef, CFGetTypeID(posValue) == AXValueGetTypeID() {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &currentAxPoint)
        }
        guard let screen = screenContainingAxPoint(currentAxPoint) ?? NSScreen.main else { return }
        let placement = settings.placement(for: screen)

        var newOrigin = placement.position.axOrigin(
            forWindowSize: size,
            screen: screen,
            xOffset: CGFloat(placement.xOffset),
            yOffset: CGFloat(placement.yOffset)
        )

        guard let positionValue = AXValueCreate(.cgPoint, &newOrigin) else { return }
        let r = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        log.info("Set position size=\(size.width)x\(size.height) → (\(newOrigin.x),\(newOrigin.y)) result=\(r.rawValue)")
    }

    /// Convert an AX point (top-left of primary screen) to NSScreen coords
    /// (bottom-left of primary screen) and find the screen that contains it.
    private func screenContainingAxPoint(_ axPoint: CGPoint) -> NSScreen? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsPoint = CGPoint(x: axPoint.x, y: primaryHeight - axPoint.y)
        return NSScreen.screens.first { $0.frame.contains(nsPoint) }
    }
}

// MARK: - C-style AX callback

private func axNotificationCallback(observer: AXObserver,
                                    element: AXUIElement,
                                    notification: CFString,
                                    refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let nanny = Unmanaged<NotificationRepositioner>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    Task { @MainActor in
        nanny.handleAXEvent(element: element, notification: name)
    }
}
