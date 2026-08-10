import AppKit
@preconcurrency import ApplicationServices
import Combine
import os

private let log    = Logger(subsystem: "com.notificationnanny", category: "repositioner")
private let axLog  = Logger(subsystem: "com.notificationnanny", category: "ax")

@MainActor
private final class Debouncer {
    private var pending: DispatchWorkItem?

    func schedule(delay: TimeInterval, action: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem(block: action)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

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
        settings.settingsDidChange
            .throttle(for: .milliseconds(8), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                guard let self, self.testGroupID != nil, let win = self.testBannerWindow else { return }
                self.snapWindow(win, stackIndex: 0)
            }
            .store(in: &cancellables)
        startObserving()
    }

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

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil; ncApp = nil; ncPid = 0
        isObserving = false
        lastSelfSetPositions.removeAll()
        lastRepositionAt.removeAll()
        generation.removeAll()
        overlayContent.removeAll()
        dismissedKeys.removeAll()
        loggedSkippedKeys.removeAll()
        resolver.invalidateAll()
        customBannerManager.dismissAll()
        logger.log("Observer stopped", tag: "AX")
    }

    private func findBannerElement(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        resolver.findBannerElement(in: el, depth: depth)
    }

    private func appName(for window: AXUIElement) -> String? {
        resolver.appName(for: window)
    }

    fileprivate func handleAXEvent(element: AXUIElement, notification: String) {
        axLog.debug("── AX event: \(notification, privacy: .public)")

        if notification == kAXUIElementDestroyedNotification as String {
            let key = CFHash(element)
            let hadOverlay = customBannerManager.isActive(key: key)
            let wasTrackedBanner = lastSelfSetPositions[key] != nil
            if hadOverlay || wasTrackedBanner {
                logger.log("Window destroyed\(hadOverlay ? " — overlay dismissed" : "")", tag: "AX")
            } else {
                axLog.debug("Window destroyed — untracked (widget/chrome churn)")
            }
            resolver.invalidate(key: key)
            lastSelfSetPositions.removeValue(forKey: key)
            lastRepositionAt.removeValue(forKey: key)
            generation.removeValue(forKey: key)
            overlayContent.removeValue(forKey: key)
            dismissedKeys.remove(key)
            loggedSkippedKeys.remove(key)
            if let bound = testBannerWindow, CFEqual(bound, element) { testBannerWindow = nil }
            stopScaleHammer()
            customBannerManager.dismiss(key: key)
            scheduleDestroySweep()
            return
        }

        if notification == kAXWindowCreatedNotification as String {
            let name = appName(for: element)
            if let name {
                logger.log("Window created — \(name)", tag: "AX")
            } else {
                let subrole = element.stringAttribute(kAXSubroleAttribute as String) ?? "none"
                logger.log("Window created — unknown (subrole: \(subrole))", tag: "AX")
            }
        }

        if notification == kAXWindowMovedNotification as String {
            if !customBannerManager.isActive(key: CFHash(element)),
               let movedAt = lastRepositionAt[CFHash(element)], Date().timeIntervalSince(movedAt) < 0.6 {
                axLog.debug("handleAXEvent: windowMoved within 0.6s of self-move — ignoring (animation churn)")
                return
            }
            let cur = element.point() ?? .zero
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
            let sz = element.size() ?? .zero
            axLog.debug("handleAXEvent: focus/mainWindow event — window size \(sz.width, format: .fixed(precision: 0))×\(sz.height, format: .fixed(precision: 0))")
            if sz.width > 700 || sz.height > 400 {
                axLog.debug("handleAXEvent: large window on focus event, skipping (likely NC panel)")
                return
            }
        }

        axLog.debug("handleAXEvent: proceeding to repositionWindow")
        repositionWindow(element)
    }

    private let destroySweepDebouncer = Debouncer()

    private func scheduleDestroySweep() {
        destroySweepDebouncer.schedule(delay: 0.12) { [weak self] in self?.repositionVisibleWindows() }
    }

    private func burstReposition() {
        if let settings, !settings.isActive {
            customBannerManager.dismissAll()
            overlayContent.removeAll()
        }
        repositionVisibleWindows()
        for delay in [0.03, 0.06, 0.1, 0.2, 0.4, 0.8, 1.5, 2.5] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.repositionVisibleWindows()
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

    private func nextGeneration(for key: CFHashCode) -> Int {
        let g = (generation[key] ?? 0) &+ 1
        generation[key] = g
        return g
    }

    private func isCurrentGeneration(_ gen: Int, for key: CFHashCode) -> Bool {
        generation[key] == gen
    }

    private func effectiveTestGroup(for window: AXUIElement) -> UUID?? {
        guard let pending = testGroupID else { return nil }
        if let bound = testBannerWindow {
            return CFEqual(bound, window) ? pending : nil
        }
        if let title = pendingTestTitle, bannerDescription(of: window)?.contains(title) == true {
            testBannerWindow = window
            return pending
        }
        return nil
    }

    private func bannerDescription(of window: AXUIElement) -> String? {
        let el = findBannerElement(in: window) ?? window
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXAttributedDescription" as CFString, &ref) == .success,
              let val = ref, CFGetTypeID(val) == CFAttributedStringGetTypeID() else { return nil }
        return CFAttributedStringGetString((val as! CFAttributedString)) as String
    }

    private static func isCapturing() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screensharing.agent").isEmpty {
            return true
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerName as String] as? String) == "screensharing" }
    }

    private static let bannerSize = CGSize(width: 372, height: 100)
    private static let maxBannerWidth: CGFloat = 480
    private static let bannerInsetFromTopRight = CGPoint(x: 14, y: 14)
    private static let stackGap: CGFloat = 8
    private static let parkPoint = CGPoint(x: -9999, y: 0)
    private var generation: [CFHashCode: Int] = [:]
    private var lastSelfSetPositions: [CFHashCode: CGPoint] = [:]
    private var lastRepositionAt: [CFHashCode: Date] = [:]
    private var overlayContent: [CFHashCode: BannerContent] = [:]
    private var dismissedKeys: Set<CFHashCode> = []
    private var loggedSkippedKeys: Set<CFHashCode> = []
    private var testGroupID: UUID?? = nil
    private var testBannerWindow: AXUIElement? = nil
    private var pendingTestTitle: String? = nil

    private let customBannerManager = CustomBannerManager()

    private var isDisplaySleeping = false
    private var pendingWakeWindows: [AXUIElement] = []
    private var lastWakeAt: Date?
    private var lastScreenChangeAt: Date?

    private func registerSleepWakeObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleDisplaySleep() } }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleDisplayWake() } }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleScreenParametersChange() } }
    }

    private let screenParamsDebouncer = Debouncer()

    private func handleScreenParametersChange() {
        lastScreenChangeAt = Date()
        logger.log("Screen configuration changed — re-evaluating banner positions", tag: "System")
        logScreenTopology(reason: "screen change")
        screenParamsDebouncer.schedule(delay: 0.4) { [weak self] in self?.burstReposition() }
    }

    private func logScreenTopology(reason: String) {
        let screens = NSScreen.screens
        let forced = settings?.targetDisplayID ?? 0
        logger.log("Displays after \(reason): \(screens.count) — forced target id=\(forced)", tag: "Display")
        for screen in screens {
            logger.log("  · \(screen.nannyLogDescriptor)", tag: "Display")
        }
    }

    private func recentDisplayEventDescription() -> String? {
        let now = Date()
        let candidates: [(String, Date?)] = [("wake", lastWakeAt), ("screen change", lastScreenChangeAt)]
        let recent = candidates
            .compactMap { label, date -> (String, TimeInterval)? in
                guard let date else { return nil }
                let elapsed = now.timeIntervalSince(date)
                return elapsed <= 5 ? (label, elapsed) : nil
            }
            .min { $0.1 < $1.1 }
        guard let (label, elapsed) = recent else { return nil }
        return "\(Int(elapsed * 1000))ms since last \(label)"
    }

    private func handleDisplaySleep() {
        guard settings?.holdWhileAsleep == true else { return }
        isDisplaySleeping = true
        logger.log("Display sleeping — holding banners", tag: "System")
        guard let ncApp else { return }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        var parkedBanners = 0
        var skippedWidgets = 0
        for window in windows {
            if isProtectedWidget(window) { skippedWidgets += 1; continue }
            setWindowPosition(window, to: Self.parkPoint)
            parkedBanners += 1
            if !pendingWakeWindows.contains(where: { CFEqual($0, window) }) {
                pendingWakeWindows.append(window)
            }
        }
        logger.log("Display sleep — parked \(parkedBanners) banner(s), left \(skippedWidgets) desktop widget(s) in place", tag: "Widget")
    }

    private func handleDisplayWake() {
        lastWakeAt = Date()
        isDisplaySleeping = false
        guard !pendingWakeWindows.isEmpty else { return }
        let queued = pendingWakeWindows
        pendingWakeWindows = []
        logger.log("Display woke — repositioning \(queued.count) held banner(s)", tag: "System")
        logScreenTopology(reason: "wake")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            for window in queued { self.repositionWindow(window) }
            if let secs = self.settings?.autoDismissSeconds {
                self.customBannerManager.resetDismissTimers(autoDismissSeconds: secs)
            }
        }
    }

    private var scaleTimer: DispatchSourceTimer?
    private var activeBannerElement: AXUIElement? = nil
    private var targetBannerSize: CGSize = .zero

    func sendTestNotification(groupID: UUID?) {
        guard testGroupID == nil else { return }
        testGroupID = .some(groupID)
        testBannerWindow = nil
        let groupLabel = groupID.map { "group \($0.uuidString.prefix(8))" } ?? "default"
        logger.log("Test notification sent — \(groupLabel), observing=\(isObserving)", tag: "Test")
        pendingTestTitle = TestNotification.send()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.testGroupID = nil
            self?.testBannerWindow = nil
            self?.pendingTestTitle = nil
        }
    }

    package func sendBurstTest(count: Int) {
        logger.log("Burst test — sending \(count) back-to-back notifications", tag: "Debug")
        TestNotification.sendBurst(count: count)
    }

    package func sendEdgeCase(_ scenario: TestNotification.Scenario) {
        logger.log("Edge case — \(scenario.label)", tag: "Debug")
        TestNotification.sendCustom(title: scenario.title, body: scenario.body)
    }

    package func dumpBannerDiagnostics() {
        logger.log("════ AX dump start ════", tag: "Debug")
        guard let ncApp else {
            logger.log("No NC handle — not observing (grant Accessibility?)", level: .warn, tag: "Debug")
            return
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            logger.log("Could not read NC windows", level: .warn, tag: "Debug")
            return
        }
        logger.log("NC PID \(ncPid) — \(windows.count) window(s)", tag: "Debug")
        for (i, w) in windows.enumerated() {
            let banner = findBannerElement(in: w) != nil
            logger.log("── window[\(i)]\(banner ? " (has banner)" : "") ──", tag: "Debug")
            dumpAXElement(w, depth: 0)
        }
        logger.log("════ AX dump end ════", tag: "Debug")
    }

    private func dumpAXElement(_ el: AXUIElement, depth: Int) {
        guard depth < 8 else { return }
        let indent = String(repeating: "· ", count: depth)
        var parts = [indent + (el.stringAttribute(kAXRoleAttribute as String) ?? "?")]
        if let sub = el.stringAttribute(kAXSubroleAttribute as String) { parts.append("[\(sub)]") }
        if let desc = el.stringAttribute("AXAttributedDescription"), !desc.isEmpty {
            parts.append("desc=\"\(desc.replacingOccurrences(of: "\n", with: "⏎"))\"")
        }
        if let v = el.stringAttribute(kAXValueAttribute as String), !v.isEmpty {
            parts.append("value=\"\(v.replacingOccurrences(of: "\n", with: "⏎"))\"")
        }
        if let p = el.point(), let s = el.size() {
            parts.append("@(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))×\(Int(s.height)))")
        }
        logger.log(parts.joined(separator: " "), tag: "Debug")
        for child in el.children() { dumpAXElement(child, depth: depth + 1) }
    }

    private struct RepositionTarget {
        let windowOrigin: CGPoint
        let windowSize: CGSize
        let placement: ScreenPlacement
        let screen: NSScreen
        let bannerOffsetInWindow: CGPoint
        let bannerSize: CGSize
    }

    private func targetOrigin(for window: AXUIElement, stackIndex: Int = 0) -> RepositionTarget? {
        guard let settings, settings.isActive else {
            log.debug("targetOrigin: skipped — disabled or snoozed")
            return nil
        }
        guard !dismissedKeys.contains(CFHash(window)) else {
            log.debug("targetOrigin: skipped — window was auto-dismissed")
            return nil
        }
        let testGroupID = effectiveTestGroup(for: window)
        if settings.pauseWhileStreaming, Self.isCapturing() {
            log.debug("targetOrigin: skipped — capturing")
            return nil
        }
        if settings.pauseDuringFocus, FocusModeMonitor.shared.isActive {
            log.debug("targetOrigin: skipped — Focus/DND active")
            return nil
        }

        let size   = window.size() ?? .zero
        let oldPos = window.point() ?? .zero

        log.debug("targetOrigin: window size=\(size.width, format: .fixed(precision: 0))×\(size.height, format: .fixed(precision: 0)) pos=(\(oldPos.x, format: .fixed(precision: 0)),\(oldPos.y, format: .fixed(precision: 0)))")

        let appNameStr: String?
        if testGroupID == nil {
            appNameStr = appName(for: window)
            if let appNameStr { settings.recordAppName(appNameStr) }
        } else {
            appNameStr = nil
        }

        let groupScreen = testGroupID != nil
            ? settings.resolvedTargetScreen(forGroupID: testGroupID!)
            : settings.resolvedTargetScreen(for: appNameStr)

        let screen: NSScreen
        if let forced = groupScreen {
            screen = forced
        } else if settings.followActiveScreen, let active = Self.activeScreen() {
            screen = active
        } else if let forced = settings.resolvedTargetScreen() {
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
            guard let bannerEl = findBannerElement(in: window) else {
                log.info("targetOrigin: skipped — large window, no banner child (NC panel/widget)")
                logSkippedOnce(window, reason: "Large NC window with no recognised banner child",
                              tag: "Banner", size: size, pos: oldPos)
                return nil
            }
            if settings.avoidNCPanel, isNCFocusedPanel(window) {
                return nil
            }
            var bSz = bannerEl.size() ?? Self.bannerSize
            if bSz.width > Self.maxBannerWidth { bSz.width = Self.bannerSize.width }
            let offsetX = size.width - bSz.width - Self.bannerInsetFromTopRight.x
            var offsetY = Self.bannerInsetFromTopRight.y
            if let bPos = bannerEl.point() {
                offsetY = bPos.y - oldPos.y
            }
            bannerOffset = CGPoint(x: offsetX, y: offsetY)
            bannerSz = bSz
        } else {
            if settings.protectDesktopWidgets, findBannerElement(in: window) == nil {
                log.info("targetOrigin: skipped — small window, no banner subrole (desktop widget)")
                logSkippedOnce(window, reason: "Protected desktop widget, left in place",
                              tag: "Widget", size: size, pos: oldPos)
                return nil
            }
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
        let testGroupID = effectiveTestGroup(for: window)
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
                customBannerManager.dismiss(key: CFHash(window))
                overlayContent.removeValue(forKey: CFHash(window))
            } else if testGroupID == nil, overlayContentChanged(for: window) {
                customBannerManager.dismiss(key: CFHash(window))
                overlayContent.removeValue(forKey: CFHash(window))
                repositionWindow(window)
                return
            } else {
                hideOffscreen(window, atX: t.windowOrigin.x)
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

        log.debug("snapWindow: setting position → (\(t.windowOrigin.x, format: .fixed(precision: 1)), \(t.windowOrigin.y, format: .fixed(precision: 1)))")
        setWindowPosition(window, to: t.windowOrigin)
    }

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

    private func isBannerReady(_ window: AXUIElement) -> Bool {
        findBannerElement(in: window) != nil && appName(for: window) != nil
    }

    private func repositionWindow(_ window: AXUIElement, attempt: Int = 0) {
        let gen = nextGeneration(for: CFHash(window))
        let testGroupID = effectiveTestGroup(for: window)

        if testGroupID == nil, attempt < 3, !isBannerReady(window) {
            let delay: Double = [0.05, 0.15, 0.35][attempt]
            logger.log("Banner not ready — retry \(attempt + 1)/3 in \(Int(delay * 1000))ms", tag: "Banner")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isCurrentGeneration(gen, for: CFHash(window)) else { return }
                self.repositionWindow(window, attempt: attempt + 1)
            }
            return
        }
        if testGroupID == nil, attempt >= 3, !isBannerReady(window) {
            let subrole = window.stringAttribute(kAXSubroleAttribute as String) ?? "none"
            let context = recentDisplayEventDescription().map { ", \($0)" } ?? ""
            logger.log("Readiness gate exhausted after 3 retries — proceeding as non-banner (window subrole: \(subrole)\(context))", tag: "Banner")
        }

        log.debug("repositionWindow: computing base target (stackIndex=0)")
        guard let baseInfo = targetOrigin(for: window, stackIndex: 0), let settings else {
            log.debug("repositionWindow: no base target or no settings — bailing")
            return
        }

        if settings.holdWhileAsleep, isDisplaySleeping {
            log.debug("repositionWindow: display sleeping — queuing window")
            setWindowPosition(window, to: Self.parkPoint)
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

        log.debug("repositionWindow: generation=\(gen) target=(\(info.windowOrigin.x, format: .fixed(precision: 1)),\(info.windowOrigin.y, format: .fixed(precision: 1))) bannerSize=\(info.bannerSize.width, format: .fixed(precision: 0))×\(info.bannerSize.height, format: .fixed(precision: 0))")

        let scale: Double
        var useCustomBanner: Bool
        let animation: BannerAnimation
        if let testGroup = testGroupID {
            scale = settings.effectiveBannerScale(forGroupID: testGroup)
            useCustomBanner = settings.shouldUseCustomBanner(forGroupID: testGroup)
            animation = settings.effectiveBannerAnimation(forGroupID: testGroup)
        } else {
            let name = appName(for: window)
            scale = settings.effectiveBannerScale(for: name)
            useCustomBanner = settings.shouldUseCustomBanner(for: name)
            animation = settings.effectiveBannerAnimation(for: name)
        }
        if isNCFocusedPanel(window) {
            useCustomBanner = false
            logger.log("Notification Center panel — forcing native move (no custom overlay)", tag: "Banner")
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

            if testGroupID != nil && !customBannerManager.isActive(key: key) && customBannerManager.hasActive {
                logger.log("Test mode: extra NC window parked off-screen", tag: "Custom")
                hideOffscreen(window, atX: info.windowOrigin.x)
                scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)
                return
            }

            if customBannerManager.isActive(key: key), !(testGroupID == nil && overlayContentChanged(for: window)) {
                hideOffscreen(window, atX: info.windowOrigin.x)
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

            let bannerEl = findBannerElement(in: window) ?? window
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
                hideOffscreen(window, atX: info.windowOrigin.x)

                let scaledWidth = info.bannerSize.width * scale
                let widthDelta = scaledWidth - info.bannerSize.width

                let bannerAXOrigin = CGPoint(
                    x: info.windowOrigin.x + info.bannerOffsetInWindow.x,
                    y: info.windowOrigin.y + info.bannerOffsetInWindow.y
                )

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

                let capturedEl = bannerEl
                let capturedName = content.appName
                let bannerBackground = testGroupID != nil
                    ? settings.effectiveBannerColor(forGroupID: testGroupID!)
                    : settings.effectiveBannerColor(for: appName(for: window))
                if bannerBackground == .clear {
                    logger.log("Custom overlay untinted — rendering with system appearance (scale=\(String(format: "%.2f", scale))×, animation=\(animation.rawValue))", tag: "Custom")
                }
                customBannerManager.showBanner(
                    content: content,
                    axTopLeft: finalAXOrigin,
                    width: scaledWidth,
                    scale: scale,
                    backgroundColor: bannerBackground,
                    textColor: settings.effectiveBannerTextColor,
                    autoDismissSeconds: settings.autoDismissSeconds,
                    animation: animation,
                    onOpen: { [weak self] in self?.handleBannerTap(appName: capturedName, bannerElement: capturedEl) },
                    onUnderlyingDismiss: { [weak self] in self?.retireUnderlyingWindow(window) },
                    key: key
                )
                if testGroupID == nil { overlayContent[key] = content }
                scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)
                return
            }
            if attempt < 3 {
                let delay: Double = [0.05, 0.15, 0.35][attempt]
                logger.log("Content extraction retry \(attempt + 1)/3 in \(Int(delay * 1000))ms", tag: "Custom")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.isCurrentGeneration(gen, for: CFHash(window)) else { return }
                    self.repositionWindow(window, attempt: attempt + 1)
                }
                return
            }
            logger.log("Content extraction failed after 3 retries — falling back to native banner", level: .warn, tag: "Custom")
        }

        if customBannerManager.isActive(key: CFHash(window)) {
            customBannerManager.dismiss(key: CFHash(window))
            overlayContent.removeValue(forKey: CFHash(window))
        }

        setWindowPosition(window, to: info.windowOrigin)

        scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)

        if settings.autoDismissSeconds > 0 {
            log.debug("repositionWindow: scheduling auto-dismiss after \(settings.autoDismissSeconds, format: .fixed(precision: 1))s")
            scheduleAutoDismiss(window: window, info: info, generation: gen)
        }
    }

    private func overlayContentChanged(for window: AXUIElement) -> Bool {
        let key = CFHash(window)
        guard let shown = overlayContent[key] else { return false }
        guard let current = extractBannerContent(from: findBannerElement(in: window) ?? window,
                                                 knownAppName: appName(for: window)) else { return false }
        return current != shown
    }

    private func extractBannerContent(from element: AXUIElement, knownAppName: String?) -> BannerContent? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXAttributedDescription" as CFString, &ref) == .success,
              let val = ref, CFGetTypeID(val) == CFAttributedStringGetTypeID() else { return nil }

        let rawStr = CFAttributedStringGetString((val as! CFAttributedString)) as String
        let str = cleanAXString(rawStr)
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
        let appName = knownAppName ?? parsedAppName

        let (title, body) = splitTitleBody(content: textPart, element: element, appName: appName)
        return BannerContent(appName: appName, title: title, body: body, appIcon: lookupIcon(for: appName))
    }

    private func splitTitleBody(content: String, element: AXUIElement, appName: String) -> (String, String) {
        for text in element.staticTextValues()
        where !text.isEmpty && text.caseInsensitiveCompare(appName) != .orderedSame && content.hasPrefix(text) {
            var body = String(content.dropFirst(text.count))
            if body.hasPrefix(", ") { body.removeFirst(2) }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text, body)
        }
        return Self.heuristicSplit(content)
    }

    private static func heuristicSplit(_ content: String) -> (String, String) {
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        if lines.count > 1 {
            return (lines.first ?? content, lines.dropFirst().joined(separator: "\n"))
        }
        let singleLine = lines.first ?? content
        if let lastComma = singleLine.range(of: ", ", options: .backwards) {
            return (String(singleLine[singleLine.startIndex..<lastComma.lowerBound]),
                    String(singleLine[lastComma.upperBound...]))
        }
        return (singleLine, "")
    }

    private func lookupIcon(for appName: String) -> NSImage? {
        let ws = NSWorkspace.shared
        if let icon = ws.runningApplications.first(where: { $0.localizedName == appName })?.icon {
            return icon
        }
        if let bundleID = ws.runningApplications.first(where: { $0.localizedName == appName })?.bundleIdentifier,
           let url = ws.urlForApplication(withBundleIdentifier: bundleID) {
            return ws.icon(forFile: url.path)
        }
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

    private func scheduleHolds(window: AXUIElement, stackIndex: Int, generation gen: Int) {
        for delay in [0.1, 0.5, 1.0, 2.0] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isCurrentGeneration(gen, for: CFHash(window)) else { return }
                self.snapWindow(window, stackIndex: stackIndex)
            }
        }
    }

    private func scheduleAutoDismiss(window: AXUIElement, info: RepositionTarget, generation gen: Int) {
        guard let delay = settings?.autoDismissSeconds, delay > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isCurrentGeneration(gen, for: CFHash(window)) else { return }
            _ = self.nextGeneration(for: CFHash(window))
            self.dismissedKeys.insert(CFHash(window))
            self.hideOffscreen(window, atX: info.windowOrigin.x)
        }
    }

    private func retireUnderlyingWindow(_ window: AXUIElement) {
        let key = CFHash(window)
        let gen = nextGeneration(for: key)
        dismissedKeys.insert(key)
        let x = window.point()?.x ?? Self.parkPoint.x
        hideOffscreen(window, atX: x)
        for delay in [0.05, 0.2, 0.5, 1.0] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isCurrentGeneration(gen, for: key),
                      self.dismissedKeys.contains(key) else { return }
                self.hideOffscreen(window, atX: x)
            }
        }
    }

    @discardableResult
    private func setWindowPosition(_ window: AXUIElement, to point: CGPoint) -> CGPoint {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return point }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        let actual = window.point() ?? point
        let key = CFHash(window)
        lastSelfSetPositions[key] = actual
        lastRepositionAt[key] = Date()
        return actual
    }

    private static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func screenContainingAxPoint(_ axPoint: CGPoint) -> NSScreen? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsPoint = CGPoint(x: axPoint.x, y: primaryHeight - axPoint.y)
        return NSScreen.screens.first { $0.frame.contains(nsPoint) }
    }

    @discardableResult
    private func hideOffscreen(_ window: AXUIElement, atX x: CGFloat) -> CGPoint {
        if isProtectedWidget(window) {
            logger.log("Refused to park a desktop widget off-screen — left it in place", level: .warn, tag: "Widget")
            return window.point() ?? .zero
        }
        return setWindowPosition(window, to: CGPoint(x: x, y: -9999))
    }

    private func isProtectedWidget(_ window: AXUIElement) -> Bool {
        settings?.protectDesktopWidgets == true && findBannerElement(in: window) == nil
    }

    private func isNCFocusedPanel(_ window: AXUIElement) -> Bool {
        guard let app = ncApp else { return false }
        var focusRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusRef) == .success,
              let fw = focusRef else { return false }
        return CFEqual(fw, window)
    }

    private func logSkippedOnce(_ window: AXUIElement, reason: String, tag: String, size: CGSize, pos: CGPoint) {
        let key = CFHash(window)
        guard !loggedSkippedKeys.contains(key) else { return }
        loggedSkippedKeys.insert(key)
        let subrole = window.stringAttribute(kAXSubroleAttribute as String) ?? "none"
        logger.log("\(reason) — \(Int(size.width))×\(Int(size.height)) at (\(Int(pos.x)),\(Int(pos.y))), subrole=\(subrole)", tag: tag)
    }
}

private func axNotificationCallback(observer: AXObserver, element: AXUIElement,
                                    notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let nanny = Unmanaged<NotificationRepositioner>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    Task { @MainActor in nanny.handleAXEvent(element: element, notification: name) }
}
