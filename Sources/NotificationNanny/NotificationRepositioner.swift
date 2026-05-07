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

        // Re-apply on every settings change. Burst over ~2.5s because macOS
        // can snap the banner back to its default position after we move it.
        settings.objectWillChange
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.burstReposition()
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
            log.info("  [\(i)] '\(title, privacy: .public)' size=\(size.width)x\(size.height) pos=(\(pos.x),\(pos.y))")
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
        detectedBannerInfo = nil
        forcedAppName = nil
    }

    // MARK: - Repositioning

    fileprivate func handleAXEvent(element: AXUIElement, notification: String) {
        log.info("AX event: \(notification, privacy: .public)")
        // kAXWindowMovedNotification also fires when WE move the window.
        // Filter those out by comparing the current position to the last
        // position we set ourselves — our own events have delta ≈ 0.
        // A real new notification makes macOS move the overlay back to its
        // default corner, which produces a large delta and passes the filter.
        if notification == kAXWindowMovedNotification as String {
            var cur = CGPoint.zero
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
               let v = ref, CFGetTypeID(v) == AXValueGetTypeID() {
                AXValueGetValue(v as! AXValue, .cgPoint, &cur)
            }
            guard hypot(cur.x - lastSelfSetPosition.x,
                        cur.y - lastSelfSetPosition.y) > 4 else { return }
        }
        repositionWindow(element)
    }

    /// Snap all visible windows into position over ~2.5s.
    /// Used for settings changes; cancels any in-flight scheduled work.
    private func burstReposition() {
        animationGeneration &+= 1
        repositionVisibleWindows()
        let delays: [TimeInterval] = [0.03, 0.06, 0.1, 0.2, 0.4, 0.8, 1.5, 2.5]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                Task { @MainActor in
                    self?.repositionVisibleWindows()
                }
            }
        }
    }

    private func repositionVisibleWindows() {
        guard let ncApp else { return }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return }
        for window in windows {
            snapWindow(window)
        }
    }

    // MARK: - Banner geometry detection

    /// Default banner geometry inside the NotificationCenter overlay window.
    private static let bannerSize = CGSize(width: 372, height: 100)
    private static let bannerInsetFromTopRight = CGPoint(x: 14, y: 14)

    /// Incremented each time repositioning starts so stale scheduled blocks bail out.
    private var animationGeneration = 0

    /// The position we most recently wrote via AXUIElementSetAttributeValue,
    /// read back after the call so it reflects any clamping macOS applied.
    /// Used to filter our own kAXWindowMovedNotification echoes in handleAXEvent.
    private var lastSelfSetPosition: CGPoint = .zero

    /// Cached result from reading actual banner bounds out of the overlay's AX tree.
    /// Nil until the first successful detection; cleared when the observer tears down.
    private struct BannerInfo {
        let offsetInWindow: CGPoint   // banner top-left relative to overlay top-left (AX coords)
        let size: CGSize
    }
    private var detectedBannerInfo: BannerInfo?

    private struct RepositionTarget {
        let windowOrigin: CGPoint
        let placement: ScreenPlacement
        let screen: NSScreen
        let bannerOffsetInWindow: CGPoint
        let bannerSize: CGSize
        let appName: String?
    }

    /// Walk the overlay window's AX child list looking for an element whose size
    /// matches a notification banner (200–700 wide, 40–250 tall).
    private func detectBannerInfo(in window: AXUIElement, windowPos: CGPoint) -> BannerInfo? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement], !children.isEmpty else { return nil }
        for child in children {
            var childPosRef: CFTypeRef?
            var childSizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &childPosRef) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &childSizeRef) == .success,
                  let posV = childPosRef, let sizeV = childSizeRef,
                  CFGetTypeID(posV) == AXValueGetTypeID(),
                  CFGetTypeID(sizeV) == AXValueGetTypeID()
            else { continue }
            var childPos = CGPoint.zero
            var childSize = CGSize.zero
            AXValueGetValue(posV as! AXValue, .cgPoint, &childPos)
            AXValueGetValue(sizeV as! AXValue, .cgSize, &childSize)
            guard childSize.width >= 200, childSize.width <= 700,
                  childSize.height >= 40,  childSize.height <= 250 else { continue }
            let offset = CGPoint(x: childPos.x - windowPos.x, y: childPos.y - windowPos.y)
            log.info("Banner detected: size=\(childSize.width)x\(childSize.height) offset=(\(offset.x),\(offset.y))")
            return BannerInfo(offsetInWindow: offset, size: childSize)
        }
        return nil
    }

    /// Forced app name for test notifications. Persists until the first banner
    /// is successfully repositioned using it, or until the 5-second expiry.
    /// Not consumed on each read so that multiple AX events for the same
    /// notification all agree on the app name.
    private var forcedAppName: String?
    private var forcedAppNameExpiry: Date = .distantPast

    func sendTest(as appName: String) {
        forcedAppName = appName
        forcedAppNameExpiry = Date().addingTimeInterval(5)
        TestNotification.send()
    }

    /// Best-effort: try window title, then first child's title/description.
    /// Returns nil if the AX tree doesn't expose the source app name.
    private func detectAppName(in window: AXUIElement) -> String? {
        if let forced = forcedAppName, Date() < forcedAppNameExpiry {
            log.info("App name via forced override: \(forced, privacy: .public)")
            return forced
        }
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty, title.count <= 60 {
            log.info("App name via window title: \(title, privacy: .public)")
            return title
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &ref) == .success,
               let s = ref as? String, !s.isEmpty, s.count <= 60 {
                log.info("App name via child title: \(s, privacy: .public)")
                return s
            }
            ref = nil
            if AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &ref) == .success,
               let s = ref as? String, !s.isEmpty, s.count <= 60 {
                log.info("App name via child description: \(s, privacy: .public)")
                return s
            }
        }
        return nil
    }

    private func targetOrigin(for window: AXUIElement) -> RepositionTarget? {
        guard let settings, settings.isEnabled else { return nil }

        var size = CGSize.zero
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &size)
        }

        var oldPos = CGPoint.zero
        var posRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
           let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &oldPos)
        }

        guard let screen = screenContainingAxPoint(oldPos) ?? NSScreen.main else { return nil }

        let appName = detectAppName(in: window)

        // Per-app override (position + offsets) takes priority over the global per-screen setting.
        let placement = (appName.flatMap { settings.appPlacement(for: $0) })
            ?? settings.placement(for: screen)

        let isOverlay = size.width > 700 || size.height > 400
        let bannerOffsetInWindow: CGPoint
        let effectiveBannerSize: CGSize

        if isOverlay {
            let info: BannerInfo
            if let cached = detectedBannerInfo {
                info = cached
            } else if let detected = detectBannerInfo(in: window, windowPos: oldPos) {
                detectedBannerInfo = detected
                info = detected
            } else {
                info = BannerInfo(
                    offsetInWindow: CGPoint(
                        x: size.width - Self.bannerInsetFromTopRight.x - Self.bannerSize.width,
                        y: Self.bannerInsetFromTopRight.y),
                    size: Self.bannerSize)
            }
            bannerOffsetInWindow = info.offsetInWindow
            effectiveBannerSize  = info.size
        } else {
            bannerOffsetInWindow = .zero
            effectiveBannerSize  = size
        }

        let bannerTarget = placement.position.axOrigin(
            forWindowSize: effectiveBannerSize,
            screen: screen,
            xOffset: CGFloat(placement.xOffset),
            yOffset: CGFloat(placement.yOffset)
        )

        let origin = CGPoint(
            x: bannerTarget.x - bannerOffsetInWindow.x,
            y: bannerTarget.y - bannerOffsetInWindow.y
        )
        return RepositionTarget(windowOrigin: origin, placement: placement,
                                screen: screen, bannerOffsetInWindow: bannerOffsetInWindow,
                                bannerSize: effectiveBannerSize, appName: appName)
    }

    /// Simple snap used by `repositionVisibleWindows` (burst/settings changes).
    private func snapWindow(_ window: AXUIElement) {
        guard let t = targetOrigin(for: window) else { return }
        var origin = t.windowOrigin
        guard let positionValue = AXValueCreate(.cgPoint, &origin) else { return }
        let setResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        log.info("snap → (\(origin.x, privacy: .public), \(origin.y, privacy: .public)) r=\(setResult.rawValue)")
    }

    /// Snap + hold schedule + app recording + optional auto-dismiss.
    /// Called from the AX event path (new notification arriving).
    private func repositionWindow(_ window: AXUIElement) {
        guard let info = targetOrigin(for: window), let settings else { return }

        let target = info.windowOrigin
        animationGeneration &+= 1
        let gen = animationGeneration

        setWindowPosition(window, to: target)
        scheduleHolds(window: window, target: target, generation: gen)

        if let appName = info.appName {
            settings.recordApp(appName)
            if appName == forcedAppName { forcedAppName = nil }
        }

        if settings.autoDismissSeconds > 0 {
            scheduleAutoDismiss(window: window, info: info, generation: gen)
        }
    }

    private func scheduleHolds(window: AXUIElement, target: CGPoint, generation: Int) {
        for delay in [0.1, 0.5, 1.0, 2.0] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard self?.animationGeneration == generation else { return }
                self?.setWindowPosition(window, to: target)
            }
        }
    }

    /// After the dismiss delay, slide the overlay above the top screen edge.
    private func scheduleAutoDismiss(window: AXUIElement, info: RepositionTarget, generation: Int) {
        let delay = settings?.autoDismissSeconds ?? 0
        guard delay > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.animationGeneration &+= 1
            let hidden = self.offScreenOrigin(for: info)
            self.setWindowPosition(window, to: hidden)
        }
    }

    /// Position that hides the overlay above the visible top edge of its screen.
    private func offScreenOrigin(for info: RepositionTarget) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? info.screen.frame.height
        let visible = info.screen.visibleFrame
        let axTop = primaryHeight - visible.maxY
        let hiddenY = axTop - info.bannerSize.height - info.bannerOffsetInWindow.y - 10
        return CGPoint(x: info.windowOrigin.x, y: hiddenY)
    }

    @discardableResult
    private func setWindowPosition(_ window: AXUIElement, to point: CGPoint) -> CGPoint {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return point }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        // Read back what macOS actually set (may differ from point if clamped).
        var ref: CFTypeRef?
        var actual = point
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &ref) == .success,
           let v = ref, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &actual)
        }
        lastSelfSetPosition = actual
        return actual
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
