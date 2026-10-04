import AppKit
@preconcurrency import ApplicationServices
import Combine
import os

private let log    = Logger(subsystem: "com.notificationnanny", category: "repositioner")
private let axLog  = Logger(subsystem: "com.notificationnanny", category: "ax")

/// NN_TIMING=1 writes how long each sweep and snap took to stderr, for
/// scripts/notify-lab's performance runs. A sweep is a row of calls into
/// Notification Center, so its cost is what dragging the position tile pays
/// per frame. Off, this is one Bool check.
private let nnTimingOn = ProcessInfo.processInfo.environment["NN_TIMING"] == "1"
private func nnTiming(_ what: String, _ ms: Double) {
    guard nnTimingOn else { return }
    FileHandle.standardError.write(Data("timing: \(what) \(String(format: "%.3f", ms)) ms\n".utf8))
}

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

    private let axController = AXObserverController()
    private var ncApp: AXUIElement? { axController.ncApp }
    private var ncPid: pid_t { axController.ncPid }

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

    package func bind(to settings: any NotificationSettingsProviding) {
        guard self.settings == nil else { return }
        self.settings = settings
        settings.settingsDidChange
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in self?.applySettingsChange() }
            .store(in: &cancellables)
        settings.settingsDidChange
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
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

        guard axController.start(onEvent: { [weak self] element, notification in
            self?.handleAXEvent(element: element, notification: notification)
        }) else {
            logger.log("NC process not found — will retry when it launches", level: .warn, tag: "AX")
            return
        }
        isObserving = true
        iconCache.prewarm()
        logger.log("Observer started — NC PID \(axController.ncPid)", tag: "AX")
        repositionVisibleWindows()
    }

    private func teardownObserver() {
        axController.stop()
        isObserving = false
        lastSelfSetPositions.removeAll()
        lastRepositionAt.removeAll()
        generation.removeAll()
        overlayContent.removeAll()
        dismissedKeys.removeAll()
        dismissTimers.cancelAll()
        customPiles.removeAll()
        bannerFirstSeen.removeAll()
        nativePiles.removeAll()
        followTimer?.cancel()
        followTimer = nil
        closedBannerIDs.removeAll()
        unreadableBannerSweeps.removeAll()
        loggedSkippedKeys.removeAll()
        resolver.invalidateAll()
        iconCache.invalidateAll()
        customBannerManager.dismissAll()
        logger.log("Observer stopped", tag: "AX")
    }

    private func findBannerElement(in el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        resolver.findBannerElement(in: el, depth: depth)
    }

    private func appName(for window: AXUIElement) -> String? {
        resolver.appName(for: window)
    }

    private func handleAXEvent(element: AXUIElement, notification: String) {
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
            dismissCustomPile(key)
            nativePiles.removeValue(forKey: key)
            loggedSkippedKeys.remove(key)
            if let bound = testBannerWindow, CFEqual(bound, element) { testBannerWindow = nil }
            stopScaleHammer()
            customBannerManager.dismiss(key: key)
            scheduleDestroySweep()
            return
        }

        if notification == kAXLayoutChangedNotification as String {
            // Measured on 26.5.2 and again on 27.0: one banner produces three of these. They
            // can also arrive for the application element rather than a window, so don't trust
            // `element` — sweep whatever windows are currently up, coalesced.
            //
            // The app name cache is keyed by window, and since macOS 26 every banner lives
            // in the same persistent host window. Without this, the first banner's app name
            // stuck to every later one until the host happened to be torn down, so a custom
            // banner showed another app's icon, or the bell if that first name had none.
            resolver.invalidateAll()
            axLog.debug("handleAXEvent: layoutChanged — scheduling sweep")
            trackLayoutChange()
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
    private var layoutTrackItems: [DispatchWorkItem] = []

    /// Sweeps while macOS animates a layout change. A banner joining a pile slides
    /// in at the top and pushes the others down over about half a second, but
    /// only the start of that raises an event, so one sweep sees the pile half
    /// moved and nothing corrects it afterwards. A bottom-anchored pile was left
    /// hanging off the screen that way. Following the slide keeps the lowest
    /// banner in place; a new event restarts the sequence. Most layout changes
    /// with nothing up are desktop widgets updating, so when the first sweep
    /// finds no banner the rest are skipped.
    private func trackLayoutChange() {
        layoutTrackItems.forEach { $0.cancel() }
        layoutTrackItems.removeAll(keepingCapacity: true)
        // A pile already up starts following at once; the slide has begun.
        if !nativePiles.isEmpty { followPiles(for: Self.followDuration) }
        schedule(after: Self.layoutTrackDelays[0]) { [weak self] in
            guard let self, self.repositionVisibleWindows() else { return }
            self.followPiles(for: Self.followDuration)
            for delay in Self.layoutTrackDelays.dropFirst() {
                self.schedule(after: delay - Self.layoutTrackDelays[0]) { [weak self] in
                    self?.repositionVisibleWindows()
                }
            }
        }
    }
    private func schedule(after delay: Double, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        layoutTrackItems.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    /// Full sweeps: one at the start of the slide and one once it has settled.
    /// Between them `followPiles` keeps native piles in place frame by frame.
    private static let layoutTrackDelays: [Double] = [0.05, 0.8]
    private static let followDuration: Double = 0.8
    /// Gliding speed in points per frame: at 60 Hz 480 pt/s, a full banner slot
    /// (64 pt) in about 0.13 s.
    private static let maxFollowStep: CGFloat = 8

    // MARK: - Following macOS's slide

    /// A native pile as the last sweep placed it, for following between sweeps.
    private struct NativePile {
        let window: AXUIElement
        let placement: ScreenPlacement
        let screen: NSScreen
        var banners: [AXUIElement]
        /// The lowest banner last frame, and whether the pile is gliding to a new
        /// resting place because that changed; see followPile.
        var lowest: AXUIElement? = nil
        var gliding = false
    }
    private var nativePiles: [CFHashCode: NativePile] = [:]
    /// Whether the last follow frame still moved a pile.
    private var followMoved = false
    private var followTimer: DispatchSourceTimer?
    private var followUntil: Double = 0

    /// macOS animates a pile inside its own window: a banner joining slides the
    /// others down, one leaving lets the rest close up, over about half a second.
    /// Sweeps can only correct the window afterwards, so a bottom-anchored pile
    /// dipped and snapped back, or dropped in one step when a gap closed. Every
    /// frame for the length of the slide, this moves the window by however much
    /// macOS has just moved the pile, so its bottom stays put and the rest glide.
    private func followPiles(for duration: Double) {
        followUntil = max(followUntil, ProcessInfo.processInfo.systemUptime + duration)
        guard followTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.followTick() }
        }
        timer.resume()
        followTimer = timer
    }

    private func followTick() {
        let started = DispatchTime.now().uptimeNanoseconds
        defer { nnTiming("follow", Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000) }
        // A glide still under way finishes even past the window.
        guard ProcessInfo.processInfo.systemUptime < followUntil || followMoved, !nativePiles.isEmpty else {
            followTimer?.cancel()
            followTimer = nil
            return
        }
        followMoved = false
        for key in Array(nativePiles.keys) { followPile(key) }
    }

    /// Keeps one pile's anchored edge where its placement puts it. At bottom and
    /// middle positions that is the bottom of the lowest banner, which doesn't
    /// depend on the banner still sliding in at the top. Top positions grow
    /// downward from a fixed top already, which macOS's own slide does right.
    private func followPile(_ key: CFHashCode) {
        guard var pile = nativePiles[key] else { return }
        switch pile.placement.position {
        case .topLeft, .topCenter, .topRight: return
        default: break
        }
        func frames() -> [CGRect]? {
            var result: [CGRect] = []
            for el in pile.banners {
                guard let p = el.point(), let s = el.size() else { return nil }
                result.append(CGRect(origin: p, size: s))
            }
            return result.isEmpty ? nil : result
        }
        var current = frames()
        if current == nil {
            // A banner left or arrived since the sweep; read the pile again.
            pile.banners = resolver.findBannerElements(in: pile.window)
            nativePiles[key] = pile
            current = frames()
        }
        guard let rects = current, let first = rects.first,
              let lowestIndex = rects.indices.max(by: { rects[$0].maxY < rects[$1].maxY }),
              let host = pile.window.point() else { return }
        let lowest = rects[lowestIndex].maxY
        // Same lowest banner as last frame: macOS is sliding the pile, and the
        // window follows exactly, so the bottom doesn't move at all. A different
        // one (a banner arrived below, or the lowest left): the pile has a new
        // resting place and glides there.
        let lowestBanner = pile.banners[lowestIndex]
        if let previous = pile.lowest, !CFEqual(previous, lowestBanner) { pile.gliding = true }
        pile.lowest = lowestBanner
        defer { nativePiles[key] = pile }
        var width = first.width
        if width > Self.maxBannerWidth { width = Self.bannerSize.width }
        let height = lowest - first.minY
        let target = pile.placement.position.axStackOrigin(
            stackSize: CGSize(width: width, height: height), screen: pile.screen,
            xOffset: CGFloat(pile.placement.xOffset), yOffset: CGFloat(pile.placement.yOffset))
        let dy = (target.y + height - lowest).rounded()
        if abs(dy) <= Self.maxFollowStep { pile.gliding = false }
        guard abs(dy) >= 1 else { return }
        let step = pile.gliding ? max(-Self.maxFollowStep, min(Self.maxFollowStep, dy)) : dy
        setWindowPosition(pile.window, to: CGPoint(x: host.x, y: host.y + step))
        followMoved = true
    }
    private let settingsSettleDebouncer = Debouncer()
    private var burstWorkItems: [DispatchWorkItem] = []

    private func scheduleDestroySweep() {
        destroySweepDebouncer.schedule(delay: 0.12) { [weak self] in self?.repositionVisibleWindows() }
    }

    /// Settings edits: move what's on screen now, once.
    ///
    /// Deliberately *not* a burst. This fires at up to 60 Hz while the position
    /// tile or a slider is being dragged, and each pass is synchronous
    /// cross-process AX IPC. Bursting per frame queued ~9 sweeps × 60 fps with a
    /// 2.5 s tail, which pinned the main thread and made dragging crawl — worse
    /// with a banner on screen, since every visible window multiplies the work.
    ///
    /// The single debounced settle pass catches changes that land mid-drag while
    /// macOS happens to be re-laying out; one drag produces one tail pass, not
    /// hundreds.
    private func applySettingsChange() {
        if let settings, !settings.isActive {
            customBannerManager.dismissAll()
            overlayContent.removeAll()
            customPiles.removeAll()
        }
        placingFromSettings = true
        repositionVisibleWindows()
        placingFromSettings = false
        settingsSettleDebouncer.schedule(delay: 0.25) { [weak self] in
            self?.repositionVisibleWindows()
        }
    }

    /// Set while a settings change places banners: a drag of the position tile
    /// must follow the pointer at once, not glide after it.
    private var placingFromSettings = false

    private static let burstDelays: [Double] = [0.03, 0.06, 0.1, 0.2, 0.4, 0.8, 1.5, 2.5]

    /// Re-asserts position on a decaying schedule, for events where macOS does its
    /// own asynchronous re-layout after the fact — a banner appearing, a display
    /// reconfiguration, waking from sleep. One pass loses that race.
    ///
    /// Overlapping bursts cancel their predecessor: without that, back-to-back
    /// notifications stack their tails on top of each other.
    private func burstReposition() {
        if let settings, !settings.isActive {
            customBannerManager.dismissAll()
            overlayContent.removeAll()
            customPiles.removeAll()
        }
        burstWorkItems.forEach { $0.cancel() }
        burstWorkItems.removeAll(keepingCapacity: true)
        repositionVisibleWindows()
        for delay in Self.burstDelays {
            let item = DispatchWorkItem { [weak self] in self?.repositionVisibleWindows() }
            burstWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    /// Returns whether any window had something to place.
    @discardableResult
    private func repositionVisibleWindows() -> Bool {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            nnTiming("sweep", ms)
        }
        guard let ncApp else {
            log.debug("repositionVisibleWindows: ncApp is nil, skipping")
            return false
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            log.debug("repositionVisibleWindows: failed to get windows from ncApp")
            return false
        }
        log.debug("repositionVisibleWindows: \(windows.count) window(s) from ncApp")
        sweepBanners = [:]
        defer { sweepBanners = nil }
        if !dismissTimers.armedIDs.isEmpty || !closedBannerIDs.isEmpty || !unreadableBannerSweeps.isEmpty
            || !bannerFirstSeen.isEmpty {
            let present = Set(windows.flatMap { banners(in: $0) }.compactMap(\.id))
            dismissTimers.prune(keeping: present)
            closedBannerIDs.formIntersection(present)
            bannerFirstSeen = bannerFirstSeen.filter { present.contains($0.key) }
            unreadableBannerSweeps = unreadableBannerSweeps.filter { present.contains($0.key) }
        }
        let baseTargets: [(AXUIElement, RepositionTarget)] = windows.compactMap { w in
            guard let t = targetOrigin(for: w, stackIndex: 0) else { return nil }
            return (w, t)
        }
        log.debug("repositionVisibleWindows: \(baseTargets.count) repositionable target(s)")
        for (i, (window, base)) in baseTargets.enumerated() {
            let idx = baseTargets[..<i].filter { sameAnchor($0.1, base) }.count
            log.debug("repositionVisibleWindows: window[\(i)] stackIndex=\(idx) anchor=\(base.placement.position.rawValue, privacy: .public)")
            // `base` was computed above with stackIndex 0, and snapWindow would
            // otherwise recompute the identical thing — doubling the AX traffic
            // of every sweep. It only carries over when this window is first at
            // its anchor, since the stack offset is baked into the target.
            snapWindow(window, stackIndex: idx, precomputed: idx == 0 ? base : nil)
        }
        return !baseTargets.isEmpty
    }

    /// A banner and its identifier, read once.
    private struct BannerRef {
        let element: AXUIElement
        let id: String?
    }

    /// Banners per window for the sweep in progress. Measuring the pile, choosing
    /// custom or native, the custom pile, auto-dismiss and pruning all need a
    /// window's banners, and each walk of the tree is a row of calls into
    /// Notification Center; within one sweep they share a single walk.
    private var sweepBanners: [CFHashCode: [BannerRef]]?

    private func banners(in window: AXUIElement) -> [BannerRef] {
        let key = CFHash(window)
        if let cached = sweepBanners?[key] { return cached }
        let found = resolver.findBannerElements(in: window).map { BannerRef(element: $0, id: $0.identifier) }
        if sweepBanners != nil { sweepBanners?[key] = found }
        return found
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

    /// Screen-sharing state doesn't change at 60 Hz, but `isCapturing()` walks the
    /// whole system window list — and it was running once per window per frame
    /// while the position tile was being dragged. Half a second of staleness is
    /// imperceptible for "pause while streaming".
    private var capturingCache: (checkedAt: Date, value: Bool)?

    private func isCapturingThrottled() -> Bool {
        if let c = capturingCache, Date().timeIntervalSince(c.checkedAt) < 0.5 { return c.value }
        let value = Self.isCapturing()
        capturingCache = (Date(), value)
        return value
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
    /// Windows parked for good. Only the fallback for banners without an identifier
    /// (one window per banner, before macOS 26); see `closeBanner(id:reason:)`.
    private var dismissedKeys: Set<CFHashCode> = []
    private let dismissTimers = BannerDismissTimers()
    /// One slot of a custom pile: a live overlay, or one playing its exit
    /// animation that keeps its place until `leavingUntil` (system uptime).
    private struct PileSlot {
        let id: String
        var size: CGSize
        /// Seconds the overlay takes to leave: its outro plus the fade after it.
        var exit: Double
        var leavingUntil: Double?
    }
    /// Custom overlays per NC window, top to bottom; see `syncCustomPile`.
    private var customPiles: [CFHashCode: [PileSlot]] = [:]
    /// Banners closed through their Close action. macOS takes a moment to remove
    /// them, and a sweep in that moment must not give them a fresh overlay.
    private var closedBannerIDs: Set<String> = []
    /// When each banner was first seen (system uptime), for ordering a custom pile.
    private var bannerFirstSeen: [String: Double] = [:]
    /// Sweeps a banner's content could not be read in, so it gets a plain overlay
    /// rather than none.
    private var unreadableBannerSweeps: [String: Int] = [:]
    private var loggedSkippedKeys: Set<CFHashCode> = []
    /// targetOrigin runs many times per sweep; log the host's stack only when it changes.
    private var lastLoggedHostBannerCount = 1
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
        if settings.pauseWhileStreaming, isCapturingThrottled() {
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
        // Height of the pile the first banner heads; see below.
        var stackHeight: CGFloat = 0

        if isOverlay {
            guard let bannerEl = findBannerElement(in: window) else {
                log.info("targetOrigin: skipped — large window, no banner child (NC panel/widget)")
                logSkippedOnce(window, reason: "Large NC window with no recognised banner child",
                              tag: "Banner", size: size, pos: oldPos)
                return nil
            }
            // Lazily, and at most once: it is a call into Notification Center.
            var panelAnswer: Bool?
            func isPanel() -> Bool {
                if let panelAnswer { return panelAnswer }
                let answer = isNCFocusedPanel(window)
                panelAnswer = answer
                return answer
            }
            if settings.avoidNCPanel, isPanel() {
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

            // Banners that are up together share this host, newest on top, and
            // macOS lays the rest out downward from it. Placing just the first one
            // pushes the others off a bottom edge, so the pile is placed as a whole,
            // from the top of the first banner to the bottom of the lowest. The open
            // Notification Center panel lists past notifications with the same
            // subroles, which are not a pile to place.
            stackHeight = bSz.height
            if !isPanel(), let bPos = bannerEl.point() {
                let banners = banners(in: window)
                let lowestBottom = banners.compactMap { ref -> CGFloat? in
                    guard let p = ref.element.point(), let s = ref.element.size() else { return nil }
                    return p.y + s.height
                }.max() ?? bPos.y + bSz.height
                stackHeight = max(bSz.height, lowestBottom - bPos.y)
                if banners.count != lastLoggedHostBannerCount {
                    lastLoggedHostBannerCount = banners.count
                    if banners.count > 1 {
                        logger.log("\(banners.count) banners up together, \(Int(stackHeight))pt tall — placing them as one pile", tag: "Banner")
                    }
                }
            }
        } else {
            if settings.protectDesktopWidgets, findBannerElement(in: window) == nil {
                log.info("targetOrigin: skipped — small window, no banner subrole (desktop widget)")
                logSkippedOnce(window, reason: "Protected desktop widget, left in place",
                              tag: "Widget", size: size, pos: oldPos)
                return nil
            }
            bannerOffset = .zero; bannerSz = size
            stackHeight = size.height
        }

        let stackDirection: CGFloat = placement.position.stacksUpward ? -1 : 1
        let stackYOffset = stackDirection * CGFloat(stackIndex) * (bannerSz.height + Self.stackGap)
        // The first banner tops the pile, so the pile's origin is its origin.
        let bannerTarget = placement.position.axStackOrigin(
            stackSize: CGSize(width: bannerSz.width, height: stackHeight), screen: screen,
            xOffset: CGFloat(placement.xOffset), yOffset: CGFloat(placement.yOffset) + stackYOffset)
        let origin = CGPoint(x: bannerTarget.x - bannerOffset.x, y: bannerTarget.y - bannerOffset.y)

        log.debug("targetOrigin: → (\(origin.x, format: .fixed(precision: 0)),\(origin.y, format: .fixed(precision: 0))) \(placement.position.rawValue, privacy: .public) screen=\(screen.displayID, privacy: .public)")
        return RepositionTarget(windowOrigin: origin, windowSize: size, placement: placement, screen: screen,
                                bannerOffsetInWindow: bannerOffset, bannerSize: bannerSz)
    }

    private func snapWindow(_ window: AXUIElement, stackIndex: Int = 0,
                            precomputed: RepositionTarget? = nil) {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            nnTiming("snap", ms)
        }
        log.debug("snapWindow: called stackIndex=\(stackIndex)")
        guard let t = precomputed ?? targetOrigin(for: window, stackIndex: stackIndex) else {
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

        // Banners with identifiers (macOS 26 on) get one overlay each, laid out as
        // a pile. The window-keyed overlay below is for banners without one.
        if hasIdentifiedBanners(window) {
            if shouldKeepCustom, !isNCFocusedPanel(window) {
                nativePiles.removeValue(forKey: CFHash(window))
                syncCustomPile(window, target: t)
                return
            }
            dismissCustomPile(CFHash(window))
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
                                         width: scaledWidth,
                                         height: t.bannerSize.height * scale,
                                         scale: CGFloat(scale))
                return
            }
        }

        log.debug("snapWindow: placing at (\(t.windowOrigin.x, format: .fixed(precision: 1)), \(t.windowOrigin.y, format: .fixed(precision: 1)))")
        placeNative(window, at: t)
        armAutoDismiss(in: window)
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

        let identified = hasIdentifiedBanners(window)
        if useCustomBanner, identified {
            nativePiles.removeValue(forKey: CFHash(window))
            syncCustomPile(window, target: info)
            scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)
            return
        }
        if identified { dismissCustomPile(CFHash(window)) }

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
                                         width: scaledWidth, height: info.bannerSize.height * scale)
                scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)
                return
            }

            let bannerEl = findBannerElement(in: window) ?? window
            // A test reads the real banner like any other notification, so the
            // overlay shows the same title and body the system banner would. The
            // fixed text is only a fallback for when extraction fails.
            var content = extractBannerContent(from: bannerEl, knownAppName: appName(for: window))
            if testGroupID != nil {
                // A test is NotificationNanny's own notification, so it carries
                // NotificationNanny's icon. Without notification permission it is
                // posted through osascript, which macOS attributes to Script Editor,
                // and reading the banner would otherwise pick up that icon.
                content = content.map {
                    BannerContent(appName: $0.appName, title: $0.title, subtitle: $0.subtitle,
                                  body: $0.body, appIcon: NSApp.applicationIconImage)
                } ?? BannerContent(
                    appName: "NotificationNanny",
                    title: "Test Notification",
                    body: "Thank you for using NotificationNanny!",
                    appIcon: NSApp.applicationIconImage
                )
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
                    height: info.bannerSize.height * scale,
                    scale: scale,
                    backgroundColor: bannerBackground,
                    textColor: settings.effectiveBannerTextColor,
                    redactContent: settings.redactBannerContent,
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

        placeNative(window, at: info)

        scheduleHolds(window: window, stackIndex: stackIndex, generation: gen)

        if settings.autoDismissSeconds > 0, !armAutoDismiss(in: window) {
            log.debug("repositionWindow: no banner identifiers — auto-dismissing the window after \(settings.autoDismissSeconds, format: .fixed(precision: 1))s")
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

        // Labelled lines are exact, including the subtitle, which the description
        // string runs together with the body. Older layouts have no identifiers,
        // so they still go through the split heuristics.
        let lines = element.identifiedTextValues()
        if let title = lines["title"] {
            return BannerContent(appName: appName, title: title, subtitle: lines["subtitle"] ?? "",
                                 body: lines["body"] ?? "", appIcon: lookupIcon(for: appName))
        }

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

    private let iconCache = AppIconCache.shared

    private func lookupIcon(for appName: String) -> NSImage? {
        iconCache.icon(for: appName)
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

    /// Starts auto-dismiss for every banner in the window that doesn't have it yet.
    /// Returns false when the banners carry no identifier, so the caller can fall
    /// back to dismissing the whole window, which is right only when each banner
    /// has a window of its own.
    @discardableResult
    private func armAutoDismiss(in window: AXUIElement) -> Bool {
        guard let delay = settings?.autoDismissSeconds, delay > 0 else { return true }
        let ids = banners(in: window).compactMap(\.id)
        guard !ids.isEmpty else { return false }
        dismissTimers.arm(ids, delay: delay) { [weak self] id in
            self?.closeBanner(id: id, reason: "Auto-dismiss")
        }
        return true
    }

    /// Closes one banner through its own Close action, the same as clicking its ✕
    /// (Clear All for several notifications of one app merged into a stack).
    /// The host window stays put, so the banners around it are unaffected.
    /// Returns false only when the banner is still up and offers no Close action;
    /// a banner that is already gone counts as closed.
    @discardableResult
    private func closeBanner(id: String, reason: String) -> Bool {
        guard let ncApp else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ncApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        for window in windows {
            for banner in resolver.findBannerElements(in: window) where banner.identifier == id {
                // Several notifications from one app merge into a stack, which
                // offers Clear All instead of Close.
                let closed = banner.performCustomAction(named: "Close")
                    || banner.performCustomAction(named: "Clear All")
                if closed { closedBannerIDs.insert(id) }
                logger.log("\(reason) — \(closed ? "closed the banner" : "banner has no Close action")",
                           level: closed ? .info : .warn, tag: "Banner")
                return closed
            }
        }
        return true
    }

    // MARK: - Custom pile

    /// Gap between overlays in a custom pile, before scale.
    private static let pileGap: CGFloat = 8

    /// Puts a native window where `t` says. A pile already up that only has to
    /// move up or down is left to followPile, which follows macOS's slide
    /// exactly or glides to a new resting place; anything new, and a settings
    /// drag, moves at once.
    private func placeNative(_ window: AXUIElement, at t: RepositionTarget) {
        if !placingFromSettings, nativePiles[CFHash(window)] != nil,
           let current = window.point(), abs(current.x - t.windowOrigin.x) < 1,
           abs(current.y - t.windowOrigin.y) > Self.maxFollowStep {
            rememberNativePile(window, target: t)
            followPiles(for: 0.4)
            return
        }
        setWindowPosition(window, to: t.windowOrigin)
        rememberNativePile(window, target: t)
    }

    /// Only the shared host (macOS 26 on) holds a pile; a small window is one banner.
    /// What the follow has learnt about the pile (its lowest banner, a glide under
    /// way) carries over, or a sweep in the middle of a change would hide it.
    private func rememberNativePile(_ window: AXUIElement, target t: RepositionTarget) {
        let key = CFHash(window)
        guard t.windowSize.width > 700 || t.windowSize.height > 400, !isNCFocusedPanel(window) else {
            nativePiles.removeValue(forKey: key)
            return
        }
        var pile = NativePile(window: window, placement: t.placement, screen: t.screen,
                              banners: banners(in: window).map(\.element))
        pile.lowest = nativePiles[key]?.lowest
        pile.gliding = nativePiles[key]?.gliding ?? false
        nativePiles[key] = pile
    }

    private func hasIdentifiedBanners(_ window: AXUIElement) -> Bool {
        let banners = banners(in: window)
        return !banners.isEmpty && banners.allSatisfy { $0.id != nil }
    }

    private func overlayKey(_ bannerID: String) -> CFHashCode {
        CFHashCode(truncatingIfNeeded: bannerID.hashValue)
    }

    private func dismissCustomPile(_ windowKey: CFHashCode) {
        for slot in customPiles.removeValue(forKey: windowKey) ?? [] {
            customBannerManager.dismiss(key: overlayKey(slot.id))
        }
    }

    /// One custom overlay per banner in the window, laid out the way the native
    /// banners are: placed as one pile (growing upward at bottom positions) and
    /// kept on screen as a whole. The host itself is parked off screen. Each
    /// overlay takes its own app's look; the pile takes the placement of the
    /// newest banner, as the native pile does. An overlay goes when its banner
    /// leaves, and dismissing an overlay closes its banner.
    private func syncCustomPile(_ window: AXUIElement, target t: RepositionTarget) {
        guard let settings else { return }
        let windowKey = CFHash(window)
        hideOffscreen(window, atX: t.windowOrigin.x)

        struct Item {
            let id: String
            let element: AXUIElement
            let name: String?
            let testGroup: UUID??
            let size: CGSize
        }
        let items: [Item] = banners(in: window).compactMap { ref in
            guard let id = ref.id, !closedBannerIDs.contains(id) else { return nil }
            let el = ref.element
            let description = el.stringAttribute("AXAttributedDescription") ?? ""
            let isTest = testGroupID != nil && pendingTestTitle.map { description.contains($0) } == true
            var size = el.size() ?? Self.bannerSize
            if size.width > Self.maxBannerWidth { size.width = Self.bannerSize.width }
            return Item(id: id, element: el, name: AppNameResolver.appName(fromDescription: description),
                        testGroup: isTest ? testGroupID : nil, size: size)
        }
        func scale(_ item: Item) -> CGFloat {
            CGFloat(item.testGroup.map { settings.effectiveBannerScale(forGroupID: $0) }
                    ?? settings.effectiveBannerScale(for: item.name))
        }

        func exit(_ item: Item) -> Double {
            let animation = item.testGroup.map { settings.effectiveBannerAnimation(forGroupID: $0) }
                ?? settings.effectiveBannerAnimation(for: item.name)
            return animation.spec.outroDuration + Self.overlayFadeOut
        }

        // Overlays whose banner went start their exit where they stand and keep
        // their slot until it is over (see PileOrder); a sweep then closes the gap.
        let now = ProcessInfo.processInfo.systemUptime
        let previous = customPiles[windowKey] ?? []
        let liveIDs = Set(items.map(\.id))
        var slots = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for var slot in previous where !liveIDs.contains(slot.id) && slot.leavingUntil == nil {
            customBannerManager.dismiss(key: overlayKey(slot.id))
            slot.leavingUntil = now + slot.exit
            slots[slot.id] = slot
            DispatchQueue.main.asyncAfter(deadline: .now() + slot.exit + 0.02) { [weak self] in
                self?.repositionVisibleWindows()
            }
        }
        let leaving = Set(slots.values.filter { ($0.leavingUntil ?? 0) > now }.map(\.id))
        for item in items where bannerFirstSeen[item.id] == nil { bannerFirstSeen[item.id] = now }
        let arranged = PileOrder.arrange(items.map(\.id), firstSeen: bannerFirstSeen,
                                         newestAtBottom: settings.newestBannerAtBottom)
        let order = PileOrder.merge(current: arranged, previous: previous.map(\.id), leaving: leaving)

        let live = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func size(of id: String) -> CGSize {
            if let item = live[id] { return CGSize(width: item.size.width * scale(item), height: item.size.height * scale(item)) }
            return slots[id]?.size ?? .zero
        }
        let sizes = order.map(size(of:))
        let gap = Self.pileGap
        let pile = CGSize(width: sizes.map(\.width).max() ?? 0,
                          height: sizes.map(\.height).reduce(0, +) + gap * CGFloat(max(0, sizes.count - 1)))
        let origin = t.placement.position.axStackOrigin(
            stackSize: pile, screen: t.screen,
            xOffset: CGFloat(t.placement.xOffset), yOffset: CGFloat(t.placement.yOffset))

        var y = origin.y
        var next: [PileSlot] = []
        var arrivals: [(id: String, item: Item, topLeft: CGPoint, size: CGSize)] = []
        for (id, size) in zip(order, sizes) {
            let x: CGFloat
            switch t.placement.position {
            case .topRight, .middleRight, .bottomRight:    x = origin.x + pile.width - size.width
            case .topCenter, .middleCenter, .bottomCenter: x = origin.x + (pile.width - size.width) / 2
            default:                                        x = origin.x
            }
            let topLeft = CGPoint(x: x, y: y)
            y += size.height + gap

            guard let item = live[id] else {
                if let slot = slots[id] { next.append(slot) }   // leaving: holds its place
                continue
            }
            let key = overlayKey(id)
            if customBannerManager.isActive(key: key) {
                customBannerManager.move(key: key, axTopLeft: topLeft,
                                         width: size.width, height: size.height, scale: scale(item),
                                         glide: !placingFromSettings)
            } else {
                arrivals.append((id, item, topLeft, size))
            }
            next.append(PileSlot(id: id, size: size, exit: exit(item), leavingUntil: nil))
        }
        customPiles[windowKey] = next

        // Make room first: while the pile glides aside, a new overlay would land
        // on the one still leaving its slot. Its slot is kept, and it slides in
        // once the glide is over.
        let settles = next.map { customBannerManager.glideEnd(key: overlayKey($0.id)) }.max() ?? 0
        if !arrivals.isEmpty, settles > now {
            DispatchQueue.main.asyncAfter(deadline: .now() + (settles - now) + 0.02) { [weak self] in
                self?.repositionVisibleWindows()
            }
            return
        }
        for arrival in arrivals {
            showPileOverlay(arrival.id, element: arrival.item.element, appName: arrival.item.name,
                            testGroup: arrival.item.testGroup, at: arrival.topLeft, size: arrival.size,
                            scale: scale(arrival.item), settings: settings)
        }
    }

    /// CustomBannerManager fades a panel out over 0.2 s after its outro.
    private static let overlayFadeOut: Double = 0.2

    private func showPileOverlay(_ id: String, element: AXUIElement, appName: String?, testGroup: UUID??,
                                 at topLeft: CGPoint, size: CGSize, scale: CGFloat,
                                 settings: any NotificationSettingsProviding) {
        var content = extractBannerContent(from: element, knownAppName: appName)
        if content == nil {
            // Not readable yet; the next sweep usually is. Past a few, show what
            // is known rather than leave a hole in the pile.
            let tries = (unreadableBannerSweeps[id] ?? 0) + 1
            unreadableBannerSweeps[id] = tries
            guard tries > 3 else { return }
            let name = appName ?? "Notification"
            content = BannerContent(appName: name, title: name, body: "", appIcon: lookupIcon(for: name))
            logger.log("Content unreadable after \(tries) sweeps — plain overlay", level: .warn, tag: "Custom")
        }
        guard var content else { return }
        unreadableBannerSweeps.removeValue(forKey: id)
        if testGroup != nil {
            // A test is NotificationNanny's own notification; see repositionWindow.
            content = BannerContent(appName: content.appName, title: content.title, subtitle: content.subtitle,
                                    body: content.body, appIcon: NSApp.applicationIconImage)
        }
        let color = testGroup.map { settings.effectiveBannerColor(forGroupID: $0) }
            ?? settings.effectiveBannerColor(for: appName)
        let animation = testGroup.map { settings.effectiveBannerAnimation(forGroupID: $0) }
            ?? settings.effectiveBannerAnimation(for: appName)
        let preview = content.title.isEmpty ? content.body.prefix(50) : content.title.prefix(50)
        logger.log("Overlay: \(content.appName) — \"\(preview)\"", tag: "Custom")
        let tapName = content.appName
        customBannerManager.showBanner(
            content: content,
            axTopLeft: topLeft,
            width: size.width,
            height: size.height,
            scale: Double(scale),
            backgroundColor: color,
            textColor: settings.effectiveBannerTextColor,
            redactContent: settings.redactBannerContent,
            autoDismissSeconds: settings.autoDismissSeconds,
            animation: animation,
            onOpen: { [weak self] in self?.handleBannerTap(appName: tapName, bannerElement: element) },
            onUnderlyingDismiss: { [weak self] in self?.closeBanner(id: id, reason: "Custom banner dismissed") },
            key: overlayKey(id)
        )
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

    /// Hides the window behind a dismissed overlay for good. Only for banners
    /// without an identifier, which have a window each; identified banners are
    /// closed one by one instead (`closeBanner`).
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
