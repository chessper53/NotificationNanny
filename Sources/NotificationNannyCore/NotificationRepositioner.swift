import AppKit
@preconcurrency import ApplicationServices
import Combine
import os

private let log = Logger(subsystem: "com.notificationnanny", category: "repositioner")

@MainActor
package final class NotificationRepositioner: ObservableObject {
    @Published private(set) var hasAccessibilityPermission: Bool
    @Published private(set) var isObserving: Bool = false

    private let permissionMonitor = AccessibilityPermissionMonitor()
    private var settings: (any NotificationSettingsProviding)?
    private var cancellables = Set<AnyCancellable>()

    nonisolated(unsafe) private var observer: AXObserver?
    private var ncApp: AXUIElement?
    private var ncPid: pid_t = 0

    package init() {
        hasAccessibilityPermission = permissionMonitor.hasPermission
        permissionMonitor.startPollingIfNeeded { [weak self] in
            self?.hasAccessibilityPermission = true
            self?.startObserving()
        }
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
        guard pid > 0 else { log.error("startObserving: no notification process found"); return }
        log.info("startObserving: pid \(pid)")
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
        return pgrepFirst(name: "usernotificationsd")
    }

    private func pgrepFirst(name: String) -> pid_t {
        let task = Process(); let pipe = Pipe()
        task.launchPath = "/usr/bin/pgrep"; task.arguments = [name]
        task.standardOutput = pipe; task.standardError = Pipe()
        try? task.run(); task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let str = String(data: data, encoding: .utf8),
           let line = str.split(separator: "\n").first,
           let pid = pid_t(line.trimmingCharacters(in: .whitespaces)) { return pid }
        return 0
    }

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil; ncApp = nil; ncPid = 0
        isObserving = false; detectedBannerInfo = nil
        windowAppNameCache.removeAll()
    }

    // MARK: - App name extraction

    private static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterBannerStack",
    ]

    private func findBannerElement(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 7 else { return nil }
        var srRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &srRef) == .success,
           let sr = srRef as? String, Self.bannerSubroles.contains(sr) { return el }
        var cRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &cRef) == .success,
              let children = cRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findBannerElement(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private func appNameFromElement(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXAttributedDescription" as CFString, &ref) == .success,
              let val = ref, CFGetTypeID(val) == CFAttributedStringGetTypeID() else { return nil }
        let str = CFAttributedStringGetString((val as! CFAttributedString)) as String
        guard let first = str.components(separatedBy: ", ").first, !first.isEmpty else { return nil }
        // Strip directional Unicode marks (e.g. U+200E prepended by WhatsApp)
        let cleaned = first
            .unicodeScalars
            .filter { !$0.properties.isDefaultIgnorableCodePoint }
            .reduce(into: "") { $0.append(Character($1)) }
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func appName(for window: AXUIElement) -> String? {
        let key = CFHash(window)
        if let cached = windowAppNameCache[key] { return cached }
        let el = findBannerElement(in: window) ?? window
        guard let name = appNameFromElement(el) else { return nil }
        windowAppNameCache[key] = name
        return name
    }

    // MARK: - Event handling

    fileprivate func handleAXEvent(element: AXUIElement, notification: String) {
        log.info("AX event: \(notification, privacy: .public)")
        if notification == kAXUIElementDestroyedNotification as String {
            repositionVisibleWindows()
            return
        }
        if notification == kAXWindowMovedNotification as String {
            var cur = CGPoint.zero; var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
               let v = ref, CFGetTypeID(v) == AXValueGetTypeID() {
                AXValueGetValue(v as! AXValue, .cgPoint, &cur)
            }
            guard hypot(cur.x - lastSelfSetPosition.x, cur.y - lastSelfSetPosition.y) > 4 else { return }
        }
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
        guard let ncApp else { return }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        // Two-pass: resolve each window's anchor first, then stack only within same-anchor groups.
        let baseTargets: [(AXUIElement, RepositionTarget)] = windows.compactMap { w in
            guard let t = targetOrigin(for: w, stackIndex: 0) else { return nil }
            return (w, t)
        }
        for (i, (window, base)) in baseTargets.enumerated() {
            let idx = baseTargets[..<i].filter { sameAnchor($0.1, base) }.count
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
    private var lastSelfSetPosition: CGPoint = .zero
    private var windowAppNameCache: [CFHashCode: String] = [:]
    // nil = not in test mode; .some(nil) = test active, screen default; .some(.some(id)) = test active, group
    private var testGroupID: UUID?? = nil
    private var testBannerWindow: AXUIElement? = nil

    func sendTestNotification(groupID: UUID?) {
        testGroupID = .some(groupID)
        testBannerWindow = nil
        TestNotification.send()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.testGroupID = nil
            self?.testBannerWindow = nil
        }
    }

    private struct BannerInfo {
        let offsetInWindow: CGPoint
        let size: CGSize
    }
    private var detectedBannerInfo: BannerInfo?

    private struct RepositionTarget {
        let windowOrigin: CGPoint
        let placement: ScreenPlacement
        let screen: NSScreen
        let bannerOffsetInWindow: CGPoint
        let bannerSize: CGSize
    }

    private func detectBannerInfo(in window: AXUIElement, windowPos: CGPoint) -> BannerInfo? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return nil }
        for child in children {
            var pRef: CFTypeRef?; var sRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &pRef) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sRef) == .success,
                  let pv = pRef, let sv = sRef,
                  CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID()
            else { continue }
            var pos = CGPoint.zero; var size = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sv as! AXValue, .cgSize, &size)
            guard size.width >= 200, size.width <= 700, size.height >= 40, size.height <= 250 else { continue }
            let offset = CGPoint(x: pos.x - windowPos.x, y: pos.y - windowPos.y)
            log.info("Banner: \(size.width)x\(size.height) offset=(\(offset.x),\(offset.y))")
            return BannerInfo(offsetInWindow: offset, size: size)
        }
        return nil
    }

    // MARK: - Repositioning

    private func targetOrigin(for window: AXUIElement, stackIndex: Int = 0) -> RepositionTarget? {
        guard let settings, settings.isEnabled else { return nil }
        if settings.pauseWhileStreaming, Self.isCapturing() { return nil }

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
            let info: BannerInfo
            if let cached = detectedBannerInfo {
                info = cached
            } else if let detected = detectBannerInfo(in: window, windowPos: oldPos) {
                detectedBannerInfo = detected; info = detected
            } else {
                info = BannerInfo(
                    offsetInWindow: CGPoint(x: size.width - Self.bannerInsetFromTopRight.x - Self.bannerSize.width,
                                           y: Self.bannerInsetFromTopRight.y),
                    size: Self.bannerSize)
            }
            bannerOffset = info.offsetInWindow; bannerSz = info.size
        } else {
            bannerOffset = .zero; bannerSz = size
        }

        let stackDirection: CGFloat = placement.position.stacksUpward ? -1 : 1
        let stackYOffset = stackDirection * CGFloat(stackIndex) * (bannerSz.height + Self.stackGap)
        let bannerTarget = placement.position.axOrigin(
            forWindowSize: bannerSz, screen: screen,
            xOffset: CGFloat(placement.xOffset), yOffset: CGFloat(placement.yOffset) + stackYOffset)
        let origin = CGPoint(x: bannerTarget.x - bannerOffset.x, y: bannerTarget.y - bannerOffset.y)

        return RepositionTarget(windowOrigin: origin, placement: placement, screen: screen,
                                bannerOffsetInWindow: bannerOffset, bannerSize: bannerSz)
    }

    private func snapWindow(_ window: AXUIElement, stackIndex: Int = 0) {
        guard let t = targetOrigin(for: window, stackIndex: stackIndex) else { return }
        if testGroupID != nil { testBannerWindow = window }
        var origin = t.windowOrigin
        guard let v = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
    }

    private func repositionWindow(_ window: AXUIElement) {
        guard let baseInfo = targetOrigin(for: window, stackIndex: 0), let settings else { return }
        let stackIndex = stackIndex(for: window, baseTarget: baseInfo)
        guard let info = targetOrigin(for: window, stackIndex: stackIndex) else { return }

        animationGeneration &+= 1
        let gen = animationGeneration

        setWindowPosition(window, to: info.windowOrigin)
        // Re-evaluate target on each hold — app name lookup may race with banner rendering.
        scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)

        if settings.autoDismissSeconds > 0 {
            scheduleAutoDismiss(window: window, info: info, generation: gen)
        }
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
            self.setWindowPosition(window, to: self.offScreenOrigin(for: info))
        }
    }

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
        var ref: CFTypeRef?; var actual = point
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &ref) == .success,
           let v = ref, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &actual)
        }
        lastSelfSetPosition = actual
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
