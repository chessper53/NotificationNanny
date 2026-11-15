import AppKit
@preconcurrency import ApplicationServices

/// Hold a physical clock press until the native panel's column is covered by its previous
/// contents, then forward it; its release follows as soon as it arrives. AXExpanded arrives after native drawing can start, and even AX parking can block.
/// The custom panel stays above this cover. No screen capture permission is requested here.
@MainActor
final class ClockOpeningShield {
    /// The screen and whether the forwarded click opens the panel.
    var onReplay: ((NSScreen, Bool) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var clocks: [(CGRect, NSScreen)] = []
    private var discoveryTimer: Timer?
    private var discovering = false
    private var app: AXUIElement?
    private var generation = 0
    private var clicks = ClockClickQueue<CGEvent, NSScreen>()
    private var processing = false
    /// The first queued press has been forwarded; its release is forwarded when it arrives.
    private var downForwarded = false
    private var closingUntil: Double = 0
    private var lastReplay: (at: Double, open: Bool)?
    private var covers: [CGDirectDisplayID: ScreenFreeze] = [:]
    private var covering = Set<CGDirectDisplayID>()
    private var removal: DispatchWorkItem?
    private var pointerMonitor: Any?
    private var precaptureTimer: Timer?
    private var precapturing = false
    private var precaptured: [CGDirectDisplayID: (image: CGImage, at: Double)] = [:]
    private let logger: NannyLogger
    private static let replayTag: Int64 = 0x4E4E434C4F434B
    private static let discoveryQueue = DispatchQueue(label: "com.notificationnanny.clock-discovery", qos: .userInitiated)

    init(logger: NannyLogger) { self.logger = logger }

    func start(app: AXUIElement) {
        self.app = app
        guard tap == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            logger.log("Clock opening cover inactive — Screen Recording isn't allowed for this app", level: .warn, tag: "Panel")
            return
        }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: clockOpeningShieldCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.log("Clock opening cover inactive — macOS refused its event tap", level: .warn, tag: "Panel")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        discoverClocks()
        logger.log("Clock opening cover ready — Screen Recording and event tap available", tag: "Panel")
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.discoverClocks() }
        }
        RunLoop.main.add(timer, forMode: .common)
        discoveryTimer = timer
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
    }

    func stop() {
        generation += 1
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        precaptureTimer?.invalidate()
        precaptureTimer = nil
        precaptured = [:]
        removal?.cancel()
        removal = nil
        covers.values.forEach { $0.hide() }
        covering.removeAll()
        // Never lose a click when settings change during a capture.
        releasePending()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        app = nil
        clocks = []
        closingUntil = 0
        lastReplay = nil
    }

    /// Geometry discovery runs outside the tap callback; no AX calls to other processes hold input.
    private func discoverClocks() {
        guard !discovering else { return }
        discovering = true
        let screens = NSScreen.screens
        let top = screens.first?.frame.maxY ?? 0
        let search = screens.map { (frame: $0.frame, id: $0.displayID) }
        let generation = generation
        Self.discoveryQueue.async { [weak self] in
            let system = AXUIElementCreateSystemWide()
            var found: [(CGRect, CGDirectDisplayID)] = []
            for item in search {
                let frame = item.frame
                for x in stride(from: Int(frame.maxX) - 25, through: Int(frame.maxX) - 400, by: -6) {
                    var element: AXUIElement?
                    guard AXUIElementCopyElementAtPosition(system, Float(x), Float(top - frame.maxY + 12), &element) == .success,
                          let element, element.identifier == "com.apple.menuextra.clock",
                          let origin = element.point(), let size = element.size() else { continue }
                    found.append((Self.hitArea(of: CGRect(origin: origin, size: size), barTop: top - frame.maxY,
                                               screenRight: frame.maxX), item.id))
                    break
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.discovering = false
                guard self.generation == generation, self.tap != nil else { return }
                self.clocks = found.compactMap { rect, id in
                    NSScreen.screens.first(where: { $0.displayID == id }).map { (rect, $0) }
                }
            }
        }
    }

    /// The cover's area: the panel column below the menu bar.
    private static func coverRect(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.maxX - min(480, screen.frame.width), y: screen.frame.minY,
               width: min(480, screen.frame.width), height: screen.visibleFrame.maxY - screen.frame.minY)
    }

    /// The clock's surroundings in AX coordinates: a pointer here is likely heading for it.
    private func approachedClock() -> NSScreen? {
        let location = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: location.x, y: top - location.y)
        return clocks.first { hit, _ in
            CGRect(x: hit.minX - 250, y: hit.minY, width: hit.width + 250, height: hit.height + 60).contains(point)
        }?.1
    }

    /// Keep a fresh cover picture while the pointer is near the clock, so a click only waits
    /// for the cover to reach the screen. Refreshes while the pointer rests there.
    private func pointerMoved() {
        guard precaptureTimer == nil, approachedClock() != nil else { return }
        precaptureNow()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.approachedClock() != nil else {
                    self.precaptureTimer?.invalidate()
                    self.precaptureTimer = nil
                    return
                }
                self.precaptureNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        precaptureTimer = timer
    }

    private func precaptureNow() {
        guard !precapturing, !processing, clicks.count == 0, let screen = approachedClock() else { return }
        // A cover on screen would be captured into the next one.
        guard covers[screen.displayID]?.isShowing != true else { return }
        precapturing = true
        let generation = generation
        let cover = covers[screen.displayID] ?? ScreenFreeze()
        covers[screen.displayID] = cover
        Task { [weak self] in
            let image = await cover.take(Self.coverRect(on: screen), on: screen)
            guard let self else { return }
            self.precapturing = false
            guard self.generation == generation, let image else { return }
            self.precaptured[screen.displayID] = (image, ProcessInfo.processInfo.systemUptime)
        }
    }

    /// macOS opens the panel from more than the clock's AX frame: the screen's top edge, a few
    /// points to its left and, for the rightmost item, the strip into the screen corner.
    nonisolated static func hitArea(of clock: CGRect, barTop: CGFloat, screenRight: CGFloat) -> CGRect {
        let left = clock.minX - 6
        let right = screenRight - clock.maxX < 40 ? screenRight + 1 : clock.maxX + 2
        return CGRect(x: left, y: barTop, width: right - left, height: clock.maxY - barTop)
    }

    fileprivate func route(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.log("Clock tap interrupted — releasing queued input", level: .warn, tag: "Panel")
            generation += 1
            releasePending()
            covers.values.forEach { $0.hide() }
            covering.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayTag else { return false }
        if type == .leftMouseDown {
            let modifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
            guard event.flags.intersection(modifiers).isEmpty,
                  let (_, screen) = clocks.first(where: { $0.0.contains(event.location) }),
                  let copy = event.copy() else { return false }
            clicks.press(copy, on: screen, missingRelease: Self.mouseUp)
            trace("queued down, \(clicks.count) clicks, processing=\(processing)")
            finishForwardedClick()
            processClicks()
            let generation = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.generation == generation,
                      !CGEventSource.buttonState(.combinedSessionState, button: .left),
                      let orphan = self.clicks.pending.last(where: { $0.up == nil }) else { return }
                self.clicks.release(Self.mouseUp(for: orphan.down))
                self.finishForwardedClick()
                self.processClicks()
            }
            return true
        }
        guard type == .leftMouseUp, let copy = event.copy(), clicks.release(copy) else { return false }
        trace("queued up, \(clicks.count) clicks, processing=\(processing)")
        finishForwardedClick()
        processClicks()
        return true
    }

    /// Forward the release of an already forwarded press, ending that click.
    private func finishForwardedClick() {
        guard downForwarded, let click = clicks.first, let up = click.up else { return }
        replay(up)
        clicks.removeFirst()
        downForwarded = false
    }

    /// Never lose input when the shield stops or its tap is interrupted.
    private func releasePending() {
        for (index, click) in clicks.pending.enumerated() {
            if index > 0 || !downForwarded { replay(click.down) }
            replay(click.up ?? Self.mouseUp(for: click.down))
        }
        clicks.removeAll()
        downForwarded = false
    }

    private func processClicks() {
        // Like the native clock, act on the press; do not wait for its release.
        guard !processing, !downForwarded, let click = clicks.first, let app else { return }
        processing = true
        let generation = generation
        Task { [weak self] in
            guard let self else { return }
            // The previous click's removal must not fire while this click is covering.
            self.removal?.cancel()
            self.removal = nil
            // A cover already in place also protects rapid close/reopen pairs. Do not recapture
            // underneath it while native content might be drawing there.
            let remaining = self.closingUntil - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1e9))
                guard self.generation == generation else {
                    self.processing = false
                    self.processClicks()
                    return
                }
                // Native close completion can order out a host that was reopened during its animation.
                // Let it finish; paired toggles queued meanwhile cancel each other.
                self.clicks.cancelPairedToggles { $0.displayID == $1.displayID }
                self.processing = false
                self.processClicks()
                return
            }
            let reportedOpen = await withCheckedContinuation { continuation in
                Self.discoveryQueue.async {
                    continuation.resume(returning: NCPanelTakeover.isPanelOpen(app))
                }
            }
            let now = ProcessInfo.processInfo.systemUptime
            // AXExpanded trails a forwarded opening click. Preserve the intent of an immediate
            // second click even before the native agent has published its first transition.
            let open = self.lastReplay.flatMap { now - $0.at < 0.4 ? $0.open : nil } ?? reportedOpen
            let covered = self.covering.contains(click.destination.displayID)
                && self.covers[click.destination.displayID]?.isShowing == true
            self.trace(String(format: "decide at %.3f: reported open=%@ treated open=%@ covered=%@", now,
                              "\(reportedOpen)", "\(open)", "\(covered)"))
            guard self.generation == generation else {
                self.processing = false
                self.processClicks()
                return
            }
            if !covered, !open {
                let screen = click.destination
                let rect = Self.coverRect(on: screen)
                let cover = self.covers[screen.displayID] ?? ScreenFreeze()
                self.covers[screen.displayID] = cover
                let ready = self.precaptured.removeValue(forKey: screen.displayID)
                    .flatMap { ProcessInfo.processInfo.systemUptime - $0.at < 0.8 ? $0.image : nil }
                self.trace("cover from \(ready == nil ? "new capture" : "precapture")")
                let image: CGImage? = if let ready { ready } else { await cover.take(rect, on: screen) }
                if let image, self.generation == generation {
                    await cover.show(image, over: rect, level: NSWindow.Level(rawValue: 22))
                    if self.generation == generation { self.covering.insert(screen.displayID) }
                    else { cover.hide() }
                } else if self.generation == generation {
                    self.logger.log("Clock opening cover unavailable — using AX parking", level: .warn, tag: "Panel")
                }
            }
            guard self.generation == generation else {
                self.processing = false
                self.processClicks()
                return
            }
            self.replay(click.down)
            self.downForwarded = true
            self.lastReplay = (ProcessInfo.processInfo.systemUptime, !open)
            if open { self.closingUntil = ProcessInfo.processInfo.systemUptime + 0.8 }
            self.onReplay?(click.destination, !open)
            self.trace("forwarded press, waited \(Int((ProcessInfo.processInfo.systemUptime - Double(click.down.timestamp) / 1e9) * 1000)) ms")
            self.processing = false
            self.finishForwardedClick()
            // Retain the cover through the native slide in and position resets, including a rapid
            // closing transition. The parking guard continues after the cover goes away.
            self.removal?.cancel()
            let removal = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.covers.values.forEach { $0.hide() }
                self.covering.removeAll()
            }
            self.removal = removal
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: removal)
            self.processClicks()
        }
    }

    private func replay(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
        event.post(tap: .cgSessionEventTap)
    }

    private static func mouseUp(for down: CGEvent) -> CGEvent {
        let up = down.copy() ?? CGEvent(source: nil)!
        up.type = .leftMouseUp
        return up
    }

    private func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["NN_TIMING"] == "1" else { return }
        FileHandle.standardError.write(Data("[clock shield] \(message)\n".utf8))
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }
}

private func clockOpeningShieldCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                        refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let shield = Unmanaged<ClockOpeningShield>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        shield.route(type, event) ? nil : Unmanaged.passUnretained(event)
    }
}
