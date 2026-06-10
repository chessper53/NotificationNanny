import AppKit
@preconcurrency import ApplicationServices
import Combine
import os

private let log    = Logger(subsystem: "com.notificationnanny", category: "repositioner")
private let axLog  = Logger(subsystem: "com.notificationnanny", category: "ax")

@MainActor
package final class NotificationRepositioner: ObservableObject {
    @Published package private(set) var hasAccessibilityPermission: Bool
    @Published package private(set) var isObserving: Bool = false

    private let permissionMonitor = AccessibilityPermissionMonitor()
    private let resolver = AppNameResolver()
    private var settings: (any NotificationSettingsProviding)?
    private var cancellables = Set<AnyCancellable>()
    private let logger: NannyLogger

    nonisolated(unsafe) private var observer: AXObserver?
    private var ncApp: AXUIElement?
    private var ncPid: pid_t = 0

    package init(logger: NannyLogger? = nil) {
        self.logger = logger ?? .shared
        hasAccessibilityPermission = permissionMonitor.hasPermission
        permissionMonitor.startPollingIfNeeded { [weak self] in
            self?.hasAccessibilityPermission = true
            self?.startObserving()
        }
        registerSleepWakeObservers()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.notificationcenterui" else { return }
            Task { @MainActor [weak self] in self?.startObserving() }
        }
    }

    deinit {
        // Remove the run loop source so the C callback can't fire on a dangling pointer.
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    package func bind(to settings: any NotificationSettingsProviding) {
        guard self.settings == nil else { return }
        self.settings = settings
        settings.settingsDidChange
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in self?.burstReposition() }
            .store(in: &cancellables)
        // Fast path for live test-banner drag — snaps the stored element directly
        // rather than querying the ncApp window list, which can be stale.
        settings.settingsDidChange
            .throttle(for: .milliseconds(8), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                guard let self, self.testGroupID != nil, let win = self.testBannerWindow else { return }
                self.snapWindow(win, stackIndex: 0)
            }
            .store(in: &cancellables)
        startObserving()
    }

    // MARK: - Accessibility permission

    func refreshAccessibilityStatus() {
        permissionMonitor.refresh()
        hasAccessibilityPermission = permissionMonitor.hasPermission
    }

    func requestAccessibilityPermission() {
        permissionMonitor.request()
        hasAccessibilityPermission = permissionMonitor.hasPermission
        permissionMonitor.startPollingIfNeeded { [weak self] in
            self?.hasAccessibilityPermission = true
            self?.startObserving()
        }
    }

    // MARK: - Observation

    func startObserving() {
        guard hasAccessibilityPermission else {
            permissionMonitor.startPollingIfNeeded { [weak self] in
                self?.hasAccessibilityPermission = true
                self?.startObserving()
            }
            return
        }
        teardownObserver()

        let pid = findNotificationProcessPid()
        guard pid > 0 else {
            logger.log("NC process not found — will retry when it launches", level: .warn, tag: "AX")
            return
        }
        let app = AXUIElementCreateApplication(pid)

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, axNotificationCallback, &newObserver) == .success,
              let newObserver else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                     kAXWindowMovedNotification, kAXMainWindowChangedNotification,
                     kAXUIElementDestroyedNotification] as [String] {
            AXObserverAddNotification(newObserver, app, name as CFString, selfPtr)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)

        self.observer = newObserver
        self.ncApp = app
        self.ncPid = pid
        self.isObserving = true
        logger.log("Observer started — NC PID \(pid)", tag: "AX")
        repositionVisibleWindows()
    }

    private func findNotificationProcessPid() -> pid_t {
        // Primary: exact bundle ID match.
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first {
            return app.processIdentifier
        }
        // Secondary: any running app whose bundle ID contains "notification".
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier?.localizedCaseInsensitiveContains("notification") == true {
                return app.processIdentifier
            }
        }
        // Fallback: find a window owner whose name contains "notification" via CGWindowList.
        // Avoids spawning subprocesses and works across macOS versions.
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  ownerName.localizedCaseInsensitiveContains("notification"),
                  let pid = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            return pid
        }
        return 0
    }

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil; ncApp = nil; ncPid = 0
        isObserving = false
        lastSelfSetPositions.removeAll()
        dismissedKeys.removeAll()
        resolver.invalidateAll()
        customBannerManager.dismissAll()
        logger.log("Observer stopped", tag: "AX")
    }

    // MARK: - App name extraction (delegated to AppNameResolver)

    private func findBannerElement(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        resolver.findBannerElement(in: el, depth: depth)
    }

    private func appName(for window: AXUIElement) -> String? {
        resolver.appName(for: window)
    }

    // MARK: - Event handling

    fileprivate func handleAXEvent(element: AXUIElement, notification: String) {
        axLog.debug("── AX event: \(notification, privacy: .public)")

        if notification == kAXUIElementDestroyedNotification as String {
            let key = CFHash(element)
            let hadOverlay = customBannerManager.isActive(key: key)
            logger.log("Window destroyed\(hadOverlay ? " — overlay dismissed" : "")", tag: "AX")
            resolver.invalidate(key: key)
            lastSelfSetPositions.removeValue(forKey: key)
            dismissedKeys.remove(key)
            stopScaleHammer()
            customBannerManager.dismiss(key: key)
            repositionVisibleWindows()
            return
        }

        if notification == kAXWindowCreatedNotification as String {
            let name = appName(for: element) ?? "unknown"
            logger.log("Window created — \(name)", tag: "AX")
        }

        if notification == kAXWindowMovedNotification as String {
            var cur = CGPoint.zero; var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
               let v = ref, CFGetTypeID(v) == AXValueGetTypeID() {
                AXValueGetValue(v as! AXValue, .cgPoint, &cur)
            }
            let lastPos = lastSelfSetPositions[CFHash(element)] ?? .zero
            let drift = hypot(cur.x - lastPos.x, cur.y - lastPos.y)
            axLog.debug("handleAXEvent: windowMoved — cur=(\(cur.x, format: .fixed(precision: 1)),\(cur.y, format: .fixed(precision: 1))) lastSelf=(\(lastPos.x, format: .fixed(precision: 1)),\(lastPos.y, format: .fixed(precision: 1))) drift=\(drift, format: .fixed(precision: 1))")
            guard drift > 4 else {
                axLog.debug("handleAXEvent: drift ≤4, ignoring (self-induced move)")
                return
            }
        }

        if notification == kAXFocusedWindowChangedNotification as String ||
           notification == kAXMainWindowChangedNotification as String {
            var sRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sRef) == .success,
               let v = sRef, CFGetTypeID(v) == AXValueGetTypeID() {
                var sz = CGSize.zero
                AXValueGetValue(v as! AXValue, .cgSize, &sz)
                axLog.debug("handleAXEvent: focus/mainWindow event — window size \(sz.width, format: .fixed(precision: 0))×\(sz.height, format: .fixed(precision: 0))")
                if sz.width > 700 || sz.height > 400 {
                    axLog.debug("handleAXEvent: large window on focus event, skipping (likely NC panel)")
                    return
                }
            }
        }

        axLog.debug("handleAXEvent: proceeding to repositionWindow")
        repositionWindow(element)
    }

    private func burstReposition() {
        animationGeneration &+= 1
        repositionVisibleWindows()
        for delay in [0.03, 0.06, 0.1, 0.2, 0.4, 0.8, 1.5, 2.5] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                Task { @MainActor in self?.repositionVisibleWindows() }
            }
        }
    }

    private func repositionVisibleWindows() {
        guard let ncApp else {
            log.debug("repositionVisibleWindows: ncApp is nil, skipping")
            return
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            log.debug("repositionVisibleWindows: failed to get windows from ncApp")
            return
        }
        log.debug("repositionVisibleWindows: \(windows.count) window(s) from ncApp")
        // Two-pass: resolve each window's anchor first, then stack only within same-anchor groups.
        let baseTargets: [(AXUIElement, RepositionTarget)] = windows.compactMap { w in
            guard let t = targetOrigin(for: w, stackIndex: 0) else { return nil }
            return (w, t)
        }
        log.debug("repositionVisibleWindows: \(baseTargets.count) repositionable target(s)")
        for (i, (window, base)) in baseTargets.enumerated() {
            let idx = baseTargets[..<i].filter { sameAnchor($0.1, base) }.count
            log.debug("repositionVisibleWindows: window[\(i)] stackIndex=\(idx) anchor=\(base.placement.position.rawValue, privacy: .public)")
            snapWindow(window, stackIndex: idx)
        }
    }

    private func stackIndex(for window: AXUIElement, baseTarget: RepositionTarget) -> Int {
        guard let ncApp else { return 0 }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return 0 }
        var count = 0
        for other in windows {
            guard !CFEqual(other, window) else { break }
            guard let t = targetOrigin(for: other, stackIndex: 0) else { continue }
            if sameAnchor(t, baseTarget) { count += 1 }
        }
        return count
    }

    private func sameAnchor(_ a: RepositionTarget, _ b: RepositionTarget) -> Bool {
        a.screen.displayID == b.screen.displayID && a.placement.position == b.placement.position
    }

    // Detects common screen-sharing/recording scenarios. Called only when the setting is on.
    // Covers built-in macOS screen sharing; third-party apps (Zoom, Teams) suppress
    // notifications themselves in most cases.
    private static func isCapturing() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screensharing.agent").isEmpty {
            return true
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerName as String] as? String) == "screensharing" }
    }

    // MARK: - Banner geometry

    private static let bannerSize = CGSize(width: 372, height: 100)
    private static let bannerInsetFromTopRight = CGPoint(x: 14, y: 14)
    private static let stackGap: CGFloat = 8
    private var animationGeneration = 0
    private var lastSelfSetPositions: [CFHashCode: CGPoint] = [:]
    // Windows we dismissed via scheduleAutoDismiss — ignored by targetOrigin so NC can't fight back.
    private var dismissedKeys: Set<CFHashCode> = []
    // nil = not in test mode; .some(nil) = test active, screen default; .some(.some(id)) = test active, group
    private var testGroupID: UUID?? = nil
    private var testBannerWindow: AXUIElement? = nil

    private let customBannerManager = CustomBannerManager()

    // MARK: - Display sleep / wake / reconfiguration

    private var isDisplaySleeping = false
    private var pendingWakeWindows: [AXUIElement] = []

    private func registerSleepWakeObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleDisplaySleep() } }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleDisplayWake() } }

        // Fired when a display is connected, disconnected, or mirroring changes.
        // Re-evaluate all visible banners against the new screen layout so custom
        // overlays don't revert to native after a display topology change.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleScreenParametersChange() } }
    }

    private func handleScreenParametersChange() {
        logger.log("Screen configuration changed — re-evaluating banner positions", tag: "System")
        // Brief delay mirrors the wake path: let the display and NC settle before
        // we read NSScreen.screens and reposition.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.burstReposition()
        }
    }

    private func handleDisplaySleep() {
        guard settings?.holdWhileAsleep == true else { return }
        isDisplaySleeping = true
        logger.log("Display sleeping — holding banners", tag: "System")
        // Move all currently-visible NC banners offscreen so they don't flicker
        // to wrong positions briefly when the display wakes.
        guard let ncApp else { return }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            setWindowPosition(window, to: CGPoint(x: -9999, y: 0))
            if !pendingWakeWindows.contains(where: { CFEqual($0, window) }) {
                pendingWakeWindows.append(window)
            }
        }
    }

    private func handleDisplayWake() {
        isDisplaySleeping = false
        guard !pendingWakeWindows.isEmpty else { return }
        let queued = pendingWakeWindows
        pendingWakeWindows = []
        logger.log("Display woke — repositioning \(queued.count) held banner(s)", tag: "System")
        // Brief delay to let the display fully initialise before repositioning.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            for window in queued { self.repositionWindow(window) }
            // Restart dismiss timers so banners that slept get their full display time.
            if let secs = self.settings?.autoDismissSeconds {
                self.customBannerManager.resetDismissTimers(autoDismissSeconds: secs)
            }
        }
    }

    // High-frequency AX size hammering: the NC process resets the banner size each layout
    // pass (~60fps). We fight it by writing the target size at the same rate.
    private var scaleTimer: DispatchSourceTimer?
    private var activeBannerElement: AXUIElement? = nil
    private var targetBannerSize: CGSize = .zero

    func sendTestNotification(groupID: UUID?) {
        guard testGroupID == nil else { return }  // one test in flight at a time
        testGroupID = .some(groupID)
        testBannerWindow = nil
        let groupLabel = groupID.map { "group \($0.uuidString.prefix(8))" } ?? "default"
        logger.log("Test notification sent — \(groupLabel), observing=\(isObserving)", tag: "Test")
        TestNotification.send()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.testGroupID = nil
            self?.testBannerWindow = nil
        }
    }

    private struct RepositionTarget {
        let windowOrigin: CGPoint
        let windowSize: CGSize
        let placement: ScreenPlacement
        let screen: NSScreen
        let bannerOffsetInWindow: CGPoint
        let bannerSize: CGSize
    }

    // MARK: - Repositioning

    private func targetOrigin(for window: AXUIElement, stackIndex: Int = 0) -> RepositionTarget? {
        guard let settings, settings.isEnabled else {
            log.debug("targetOrigin: skipped — disabled")
            return nil
        }
        guard !dismissedKeys.contains(CFHash(window)) else {
            log.debug("targetOrigin: skipped — window was auto-dismissed")
            return nil
        }
        if settings.pauseWhileStreaming, Self.isCapturing() {
            log.debug("targetOrigin: skipped — capturing")
            return nil
        }

        var size = CGSize.zero
        var sRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sRef) == .success,
           let v = sRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &size)
        }

        var oldPos = CGPoint.zero
        var pRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pRef) == .success,
           let v = pRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &oldPos)
        }

        log.debug("targetOrigin: window size=\(size.width, format: .fixed(precision: 0))×\(size.height, format: .fixed(precision: 0)) pos=(\(oldPos.x, format: .fixed(precision: 0)),\(oldPos.y, format: .fixed(precision: 0)))")

        // Resolve app name first — needed for both screen and placement lookup.
        let appNameStr: String?
        if testGroupID == nil {
            appNameStr = appName(for: window)
            if let appNameStr { settings.recordAppName(appNameStr) }
        } else {
            appNameStr = nil
        }

        // Screen priority: exception override > global override > banner's current screen.
        let groupDisplayID = testGroupID != nil
            ? settings.targetDisplay(forGroupID: testGroupID!)
            : settings.targetDisplay(for: appNameStr)

        let screen: NSScreen
        if groupDisplayID != 0,
           let forced = NSScreen.screens.first(where: { $0.displayID == groupDisplayID }) {
            screen = forced
        } else if settings.targetDisplayID != 0,
           let forced = NSScreen.screens.first(where: { $0.displayID == settings.targetDisplayID }) {
            screen = forced
        } else {
            guard let s = screenContainingAxPoint(oldPos) ?? NSScreen.main else { return nil }
            screen = s
        }

        let placement: ScreenPlacement
        if let testGroup = testGroupID {
            placement = settings.placement(forGroupID: testGroup, screen: screen)
        } else {
            placement = settings.placement(for: appNameStr, screen: screen)
        }

        let isOverlay = size.width > 700 || size.height > 400
        let bannerOffset: CGPoint
        let bannerSz: CGSize

        if isOverlay {
            // Large window — could be an NC overlay containing a banner (macOS 26+)
            // or the NC panel / widget shelf (opened by clicking the clock). Only proceed
            // if the AX tree contains an actual notification banner element.
            guard let bannerEl = findBannerElement(in: window) else {
                log.info("targetOrigin: skipped — large window, no banner child (NC panel/widget)")
                return nil
            }
            // The NC panel (opened by clicking the clock) immediately becomes the app's
            // focused window. System-delivered notification banners don't take focus.
            // Skip repositioning if this window is already the NC process's focused window.
            if settings.avoidNCPanel, let app = ncApp {
                var focusRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusRef) == .success,
                   let fw = focusRef, CFEqual(fw, window) {
                    return nil
                }
            }
            // Size from AX — reliable, doesn't change during animation.
            var bSRef: CFTypeRef?
            var bSz = Self.bannerSize
            if AXUIElementCopyAttributeValue(bannerEl, kAXSizeAttribute as CFString, &bSRef) == .success,
               let sv = bSRef, CFGetTypeID(sv) == AXValueGetTypeID() {
                AXValueGetValue(sv as! AXValue, .cgSize, &bSz)
            }
            // x: the banner slides in from the right during its entrance animation, so
            // its screen-x is unstable until animation ends. Derive analytically instead:
            // the banner always sits bannerInsetFromTopRight.x px from the window's right edge.
            let offsetX = size.width - bSz.width - Self.bannerInsetFromTopRight.x
            // y: banner animates horizontally only, so screen-y is stable — read from AX.
            var offsetY = Self.bannerInsetFromTopRight.y
            var bPRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(bannerEl, kAXPositionAttribute as CFString, &bPRef) == .success,
               let pv = bPRef, CFGetTypeID(pv) == AXValueGetTypeID() {
                var bPos = CGPoint.zero
                AXValueGetValue(pv as! AXValue, .cgPoint, &bPos)
                offsetY = bPos.y - oldPos.y
            }
            bannerOffset = CGPoint(x: offsetX, y: offsetY)
            bannerSz = bSz
        } else {
            bannerOffset = .zero; bannerSz = size
        }

        let stackDirection: CGFloat = placement.position.stacksUpward ? -1 : 1
        let stackYOffset = stackDirection * CGFloat(stackIndex) * (bannerSz.height + Self.stackGap)
        let bannerTarget = placement.position.axOrigin(
            forWindowSize: bannerSz, screen: screen,
            xOffset: CGFloat(placement.xOffset), yOffset: CGFloat(placement.yOffset) + stackYOffset)
        let origin = CGPoint(x: bannerTarget.x - bannerOffset.x, y: bannerTarget.y - bannerOffset.y)

        log.debug("targetOrigin: → (\(origin.x, format: .fixed(precision: 0)),\(origin.y, format: .fixed(precision: 0))) \(placement.position.rawValue, privacy: .public) screen=\(screen.displayID, privacy: .public)")
        return RepositionTarget(windowOrigin: origin, windowSize: size, placement: placement, screen: screen,
                                bannerOffsetInWindow: bannerOffset, bannerSize: bannerSz)
    }

    private func snapWindow(_ window: AXUIElement, stackIndex: Int = 0) {
        log.debug("snapWindow: called stackIndex=\(stackIndex)")
        guard let t = targetOrigin(for: window, stackIndex: stackIndex) else {
            log.debug("snapWindow: no target origin, bailing")
            return
        }
        if testGroupID != nil { testBannerWindow = window }

        let shouldKeepCustom: Bool
        if let testGroup = testGroupID {
            shouldKeepCustom = settings?.shouldUseCustomBanner(forGroupID: testGroup) ?? false
        } else {
            shouldKeepCustom = settings?.shouldUseCustomBanner(for: appName(for: window)) ?? false
        }
        let scale: Double
        if let testGroup = testGroupID {
            scale = settings?.effectiveBannerScale(forGroupID: testGroup) ?? 1.0
        } else {
            scale = settings?.effectiveBannerScale(for: appName(for: window)) ?? 1.0
        }

        if customBannerManager.isActive(key: CFHash(window)) {
            if !shouldKeepCustom {
                // Mode/scale changed to native — dismiss overlay, fall through to native path.
                customBannerManager.dismiss(key: CFHash(window))
            } else {
                // Custom overlay is showing — keep the real NC banner off-screen and move our panel.
                setWindowPosition(window, to: CGPoint(x: t.windowOrigin.x, y: -9999))
                let bannerAXOrigin = CGPoint(
                    x: t.windowOrigin.x + t.bannerOffsetInWindow.x,
                    y: t.windowOrigin.y + t.bannerOffsetInWindow.y
                )
                let scaledWidth = t.bannerSize.width * scale
                let widthDelta = scaledWidth - t.bannerSize.width
                let anchoredX: CGFloat
                switch t.placement.position {
                case .topRight, .middleRight, .bottomRight:    anchoredX = bannerAXOrigin.x - widthDelta
                case .topCenter, .middleCenter, .bottomCenter: anchoredX = bannerAXOrigin.x - widthDelta / 2
                default:                                        anchoredX = bannerAXOrigin.x
                }
                customBannerManager.move(key: CFHash(window),
                                         axTopLeft: CGPoint(x: anchoredX, y: bannerAXOrigin.y),
                                         width: scaledWidth)
                return
            }
        }

        // -- Position --
        log.debug("snapWindow: setting position → (\(t.windowOrigin.x, format: .fixed(precision: 1)), \(t.windowOrigin.y, format: .fixed(precision: 1)))")
        setWindowPosition(window, to: t.windowOrigin)
    }

    // MARK: - Scale hammer (60fps AX size write to fight NC layout reset)

    private func startScaleHammer(bannerElement: AXUIElement, naturalSize: CGSize, scale: Double) {
        stopScaleHammer()
        guard abs(scale - 1.0) > 0.001 else { return }
        let target = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        activeBannerElement = bannerElement
        targetBannerSize = target
        log.info("scaleHammer: starting — \(Int(target.width))×\(Int(target.height)) at \(String(format: "%.2f", scale))×")

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        var writeCount = 0
        timer.setEventHandler { [weak self] in
            guard let self, let el = self.activeBannerElement else { return }
            var sz = self.targetBannerSize
            guard let v = AXValueCreate(.cgSize, &sz) else { return }
            AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
            writeCount += 1
        }
        timer.resume()
        scaleTimer = timer
    }

    private func stopScaleHammer() {
        if let t = scaleTimer { t.cancel(); scaleTimer = nil; log.info("scaleHammer: stopped") }
        activeBannerElement = nil
    }

    private func repositionWindow(_ window: AXUIElement, attempt: Int = 0) {
        log.debug("repositionWindow: computing base target (stackIndex=0)")
        guard let baseInfo = targetOrigin(for: window, stackIndex: 0), let settings else {
            log.debug("repositionWindow: no base target or no settings — bailing")
            return
        }

        if settings.holdWhileAsleep, isDisplaySleeping {
            log.debug("repositionWindow: display sleeping — queuing window")
            setWindowPosition(window, to: CGPoint(x: -9999, y: 0))
            if !pendingWakeWindows.contains(where: { CFEqual($0, window) }) {
                pendingWakeWindows.append(window)
            }
            return
        }
        let stackIndex = stackIndex(for: window, baseTarget: baseInfo)
        log.debug("repositionWindow: resolved stackIndex=\(stackIndex)")
        guard let info = targetOrigin(for: window, stackIndex: stackIndex) else {
            log.debug("repositionWindow: no target for stackIndex=\(stackIndex) — bailing")
            return
        }

        animationGeneration &+= 1
        let gen = animationGeneration
        log.debug("repositionWindow: animationGeneration=\(gen) target=(\(info.windowOrigin.x, format: .fixed(precision: 1)),\(info.windowOrigin.y, format: .fixed(precision: 1))) bannerSize=\(info.bannerSize.width, format: .fixed(precision: 0))×\(info.bannerSize.height, format: .fixed(precision: 0))")

        let scale: Double
        let useCustomBanner: Bool
        if let testGroup = testGroupID {
            scale = settings.effectiveBannerScale(forGroupID: testGroup)
            useCustomBanner = settings.shouldUseCustomBanner(forGroupID: testGroup)
        } else {
            let name = appName(for: window)
            scale = settings.effectiveBannerScale(for: name)
            useCustomBanner = settings.shouldUseCustomBanner(for: name)
        }
        let resolvedName: String
        if testGroupID != nil { resolvedName = "Test" } else { resolvedName = appName(for: window) ?? "unknown" }
        let modeLabel = useCustomBanner ? "custom" : "native"
        let scaleLabel = scale != 1.0 ? " \(String(format: "%.0f%%", scale * 100))" : ""
        logger.log("\(resolvedName) → \(info.placement.position.rawValue), \(modeLabel)\(scaleLabel), pos (\(Int(info.windowOrigin.x)), \(Int(info.windowOrigin.y)))", tag: "Banner")

        if useCustomBanner {
            let key = CFHash(window)
            let activeState = customBannerManager.isActive(key: key) ? "already active" : "new"
            logger.log("Custom [\(resolvedName)] \(activeState), hasOtherActive=\(customBannerManager.hasActive), attempt=\(attempt)", tag: "Custom")

            // In test mode, only allow one overlay at a time. Accumulated old NC windows
            // (from previous test clicks that NC never dismissed) get parked off-screen.
            if testGroupID != nil && !customBannerManager.isActive(key: key) && customBannerManager.hasActive {
                logger.log("Test mode: extra NC window parked off-screen", tag: "Custom")
                setWindowPosition(window, to: CGPoint(x: info.windowOrigin.x, y: -9999))
                scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)
                return
            }

            // If an overlay is already live for this window, just reposition it — don't recreate.
            if customBannerManager.isActive(key: key) {
                setWindowPosition(window, to: CGPoint(x: info.windowOrigin.x, y: -9999))
                let scaledWidth = info.bannerSize.width * scale
                let widthDelta = scaledWidth - info.bannerSize.width
                let bannerAXOrigin = CGPoint(x: info.windowOrigin.x + info.bannerOffsetInWindow.x,
                                             y: info.windowOrigin.y + info.bannerOffsetInWindow.y)
                let anchoredX: CGFloat
                switch info.placement.position {
                case .topRight, .middleRight, .bottomRight:    anchoredX = bannerAXOrigin.x - widthDelta
                case .topCenter, .middleCenter, .bottomCenter: anchoredX = bannerAXOrigin.x - widthDelta / 2
                default:                                        anchoredX = bannerAXOrigin.x
                }
                customBannerManager.move(key: key, axTopLeft: CGPoint(x: anchoredX, y: bannerAXOrigin.y),
                                         width: scaledWidth)
                scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)
                return
            }

            // Custom overlay path: suppress the real NC banner, show our own at the configured scale.
            let bannerEl = findBannerElement(in: window) ?? window
            // In test mode, hardcode the content so the osascript comma-separated AX
            // format doesn't cause parsing issues.
            let content: BannerContent?
            if testGroupID != nil {
                content = BannerContent(
                    appName: "NotificationNanny",
                    title: "Test Notification",
                    body: "Thank you for using NotificationNanny!",
                    appIcon: nil
                )
            } else {
                content = extractBannerContent(from: bannerEl, knownAppName: appName(for: window))
            }
            if let content {
                let preview = content.title.isEmpty ? content.body.prefix(50) : content.title.prefix(50)
                logger.log("Overlay: \(content.appName) — \"\(preview)\"", tag: "Custom")
                setWindowPosition(window, to: CGPoint(x: info.windowOrigin.x, y: -9999))

                // Width grows modestly with scale so text has room; height is content-driven.
                let scaledWidth = info.bannerSize.width * scale
                let widthDelta = scaledWidth - info.bannerSize.width

                // AX origin of the natural banner (stacking already baked in via targetOrigin).
                let bannerAXOrigin = CGPoint(
                    x: info.windowOrigin.x + info.bannerOffsetInWindow.x,
                    y: info.windowOrigin.y + info.bannerOffsetInWindow.y
                )

                // Adjust X so the banner stays anchored to the correct edge.
                let anchoredX: CGFloat
                switch info.placement.position {
                case .topRight, .middleRight, .bottomRight:
                    anchoredX = bannerAXOrigin.x - widthDelta
                case .topCenter, .middleCenter, .bottomCenter:
                    anchoredX = bannerAXOrigin.x - widthDelta / 2
                default:
                    anchoredX = bannerAXOrigin.x
                }
                let finalAXOrigin = CGPoint(x: anchoredX, y: bannerAXOrigin.y)

                let key = CFHash(window)
                let capturedEl = bannerEl
                let capturedName = content.appName
                customBannerManager.showBanner(
                    content: content,
                    axTopLeft: finalAXOrigin,
                    width: scaledWidth,
                    scale: scale,
                    backgroundColor: testGroupID != nil
                        ? settings.effectiveBannerColor(forGroupID: testGroupID!)
                        : settings.effectiveBannerColor(for: appName(for: window)),
                    autoDismissSeconds: settings.autoDismissSeconds,
                    animation: settings.bannerAnimation,
                    onOpen: { [weak self] in self?.handleBannerTap(appName: capturedName, bannerElement: capturedEl) },
                    key: key
                )
                // Keep holds running so the real banner stays off-screen if NC fights us.
                scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)
                return
            }
            // AXAttributedDescription may not be populated yet when the banner first appears.
            // Retry a few times before giving up and falling back to the native banner.
            if attempt < 3 {
                let delay: Double = [0.05, 0.15, 0.35][attempt]
                logger.log("Content extraction retry \(attempt + 1)/3 in \(Int(delay * 1000))ms", tag: "Custom")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.animationGeneration == gen else { return }
                    self.repositionWindow(window, attempt: attempt + 1)
                }
                return
            }
            logger.log("Content extraction failed after 3 retries — falling back to native banner", level: .warn, tag: "Custom")
        }

        setWindowPosition(window, to: info.windowOrigin)

        // Re-evaluate target on each hold — app name lookup may race with banner rendering.
        scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)

        if settings.autoDismissSeconds > 0 {
            log.debug("repositionWindow: scheduling auto-dismiss after \(settings.autoDismissSeconds, format: .fixed(precision: 1))s")
            scheduleAutoDismiss(window: window, info: info, generation: gen)
        }
    }

    // MARK: - Custom overlay helpers

    private func extractBannerContent(from element: AXUIElement, knownAppName: String?) -> BannerContent? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXAttributedDescription" as CFString, &ref) == .success,
              let val = ref, CFGetTypeID(val) == CFAttributedStringGetTypeID() else { return nil }

        let rawStr = CFAttributedStringGetString((val as! CFAttributedString)) as String
        let str = rawStr.unicodeScalars
            .filter { !$0.properties.isDefaultIgnorableCodePoint }
            .reduce(into: "") { $0.append(Character($1)) }
            .trimmingCharacters(in: .whitespaces)
        guard !str.isEmpty else { return nil }

        let parsedAppName: String
        let textPart: String
        if let commaRange = str.range(of: ", ") {
            parsedAppName = String(str[str.startIndex..<commaRange.lowerBound])
            textPart = String(str[commaRange.upperBound...])
        } else {
            parsedAppName = knownAppName ?? str
            textPart = str
        }

        let lines = textPart.components(separatedBy: "\n").filter { !$0.isEmpty }
        let title: String
        let body: String
        if lines.count > 1 {
            title = lines.first ?? textPart
            body = lines.dropFirst().joined(separator: "\n")
        } else {
            // No newline separator — split on the last ", " so e.g. "Sender Name, message"
            // renders as a proper title + body rather than one long wrapping title line.
            let singleLine = lines.first ?? textPart
            if let lastComma = singleLine.range(of: ", ", options: .backwards) {
                title = String(singleLine[singleLine.startIndex..<lastComma.lowerBound])
                body  = String(singleLine[lastComma.upperBound...])
            } else {
                title = singleLine
                body  = ""
            }
        }
        let appName = knownAppName ?? parsedAppName
        return BannerContent(appName: appName, title: title, body: body, appIcon: lookupIcon(for: appName))
    }

    private func lookupIcon(for appName: String) -> NSImage? {
        let ws = NSWorkspace.shared
        // Primary: running app list — cheapest, handles non-standard install paths.
        if let icon = ws.runningApplications.first(where: { $0.localizedName == appName })?.icon {
            return icon
        }
        // Secondary: if a running app with a known bundle ID can be resolved to a URL, use that.
        if let bundleID = ws.runningApplications.first(where: { $0.localizedName == appName })?.bundleIdentifier,
           let url = ws.urlForApplication(withBundleIdentifier: bundleID) {
            return ws.icon(forFile: url.path)
        }
        // Fallback: scan common install directories by display name.
        let dirs = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        for dir in dirs {
            let path = "\(dir)/\(appName).app"
            if FileManager.default.fileExists(atPath: path) { return ws.icon(forFile: path) }
        }
        return nil
    }

    private func handleBannerTap(appName: String, bannerElement: AXUIElement) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
            app.activate()
        }
        AXUIElementPerformAction(bannerElement, kAXPressAction as CFString)
    }

    private func scheduleHolds(window: AXUIElement, stackIndex: Int, generation: Int) {
        for delay in [0.1, 0.5, 1.0, 2.0] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                self.snapWindow(window, stackIndex: stackIndex)
            }
        }
    }

    private func scheduleAutoDismiss(window: AXUIElement, info: RepositionTarget, generation: Int) {
        guard let delay = settings?.autoDismissSeconds, delay > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.animationGeneration &+= 1
            // Mark dismissed before moving so any concurrent AX event can't re-show the banner.
            self.dismissedKeys.insert(CFHash(window))
            self.setWindowPosition(window, to: CGPoint(x: info.windowOrigin.x, y: -9999))
        }
    }

    @discardableResult
    private func setWindowPosition(_ window: AXUIElement, to point: CGPoint) -> CGPoint {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return point }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        var ref: CFTypeRef?; var actual = point
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &ref) == .success,
           let v = ref, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &actual)
        }
        lastSelfSetPositions[CFHash(window)] = actual
        return actual
    }

    private func screenContainingAxPoint(_ axPoint: CGPoint) -> NSScreen? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsPoint = CGPoint(x: axPoint.x, y: primaryHeight - axPoint.y)
        return NSScreen.screens.first { $0.frame.contains(nsPoint) }
    }
}

// MARK: - C callback

private func axNotificationCallback(observer: AXObserver, element: AXUIElement,
                                    notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let nanny = Unmanaged<NotificationRepositioner>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    Task { @MainActor in nanny.handleAXEvent(element: element, notification: name) }
}
