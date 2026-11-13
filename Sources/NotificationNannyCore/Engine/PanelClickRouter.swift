import AppKit

/// Routes clicks directly to our panel so Notification Center does not treat them as outside
/// clicks.
/// The Accessibility event tap is active only while the panel is visible.
@MainActor
final class PanelClickRouter {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private weak var window: NSWindow?
    /// Also intercept Settings clicks so dragging placement does not close Notification Center.
    var otherWindows: () -> [NSWindow] = { [] }
    /// Keep a drag and its release with the window where the press began.
    private weak var target: NSWindow?
    /// For a window other than our panel, the view the click went to.
    private weak var targetView: NSView?
    /// Lets every click through, for one passed on to a window under ours on purpose.
    var passThrough = false

    private static let mouseTypes: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]

    /// Returns false if the event tap cannot be created; the caller must then leave the native
    /// panel visible.
    @discardableResult
    func start(for window: NSWindow) -> Bool {
        self.window = window
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
        let mask = Self.mouseTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: panelClickRouterCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        target = nil
        window = nil
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }

    /// Whether to swallow `event`; if so it has been handed to our window.
    fileprivate func route(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .leftMouseDown, ProcessInfo.processInfo.environment["NN_TIMING"] == "1" { // Measure the main thread wait from the
                                                                                             // event timestamp.
            let waited = Int((ProcessInfo.processInfo.systemUptime - Double(event.timestamp) / 1e9) * 1000)
            FileHandle.standardError.write(Data("[router] down seen \(waited) ms after the click, panel visible=\(window?.isVisible ?? false) pass=\(passThrough) uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
        }
        guard !passThrough, let panel = window, panel.isVisible else { return false }
        let point = Self.appKitPoint(event.location)
        let isDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
        let isUp = type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp
        if isDown { target = Self.window(at: point, among: [panel] + otherWindows()) }
        guard let window = target else { return false }
        if isUp { target = nil }

        let inWindow = NSPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        guard let kind = Self.appKitType(type),
              let ns = NSEvent.mouseEvent(
                with: kind, location: inWindow, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: Int(event.getIntegerValueField(.mouseEventClickState)),
                pressure: isUp ? 0 : 1)
        else { return false }
        // Dispatch outside the tap callback; a slow handler would disable the tap.
        if window === panel {
            if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" {
                FileHandle.standardError.write(Data("[router] \(ns.type.rawValue) to panel at \(ns.locationInWindow) uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
            }
            DispatchQueue.main.async { [weak window] in window?.sendEvent(ns) }
        } else {
            // Send events directly to the Settings view because the inactive window cannot take a
            // keying click.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                if isDown {
                    let frameView = window.contentView?.superview ?? window.contentView
                    self.targetView = frameView?.hitTest(frameView?.convert(ns.locationInWindow, from: nil) ?? .zero)
                }
                guard let view = self.targetView else { return }
                switch ns.type {
                case .leftMouseDown: view.mouseDown(with: ns)
                case .leftMouseDragged: view.mouseDragged(with: ns)
                case .leftMouseUp: view.mouseUp(with: ns)
                case .rightMouseDown: view.rightMouseDown(with: ns)
                case .rightMouseDragged: view.rightMouseDragged(with: ns)
                case .rightMouseUp: view.rightMouseUp(with: ns)
                case .otherMouseDown: view.otherMouseDown(with: ns)
                case .otherMouseDragged: view.otherMouseDragged(with: ns)
                case .otherMouseUp: view.otherMouseUp(with: ns)
                default: break
                }
                if isUp { self.targetView = nil }
            }
        }
        return true
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Only route to ours if it is frontmost across all apps at the click position.
    private static func window(at point: NSPoint, among windows: [NSWindow]) -> NSWindow? {
        let front = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        return windows.first { $0.isVisible && $0.windowNumber == front && $0.frame.contains(point) }
    }

    /// Convert the event tap's top left origin to AppKit's bottom left origin on the main display.
    private static func appKitPoint(_ p: CGPoint) -> NSPoint {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x: p.x, y: top - p.y)
    }

    private static func appKitType(_ type: CGEventType) -> NSEvent.EventType? {
        switch type {
        case .leftMouseDown: return .leftMouseDown
        case .leftMouseUp: return .leftMouseUp
        case .leftMouseDragged: return .leftMouseDragged
        case .rightMouseDown: return .rightMouseDown
        case .rightMouseUp: return .rightMouseUp
        case .rightMouseDragged: return .rightMouseDragged
        case .otherMouseDown: return .otherMouseDown
        case .otherMouseUp: return .otherMouseUp
        case .otherMouseDragged: return .otherMouseDragged
        default: return nil
        }
    }
}

private func panelClickRouterCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                      refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let router = Unmanaged<PanelClickRouter>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    return MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            router.reenable()
            return Unmanaged.passUnretained(event)
        }
        return router.route(type, event) ? nil : Unmanaged.passUnretained(event)
    }
}
