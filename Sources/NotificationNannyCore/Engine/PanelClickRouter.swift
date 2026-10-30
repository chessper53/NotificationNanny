import AppKit

/// Delivers clicks on our Notification Center panel without Notification Center seeing them.
///
/// Notification Center closes its panel on any click outside it, including a click on a
/// non-activating panel of ours, so a plain window on top would close the very panel it is
/// standing in for at the first click. An event tap at the head of the session takes the
/// mouse events that start inside our panel out of the stream and hands them straight to
/// the window, so nothing else hears them and Notification Center's panel stays open.
/// Clicks anywhere else pass untouched, and Notification Center closes its panel as usual.
/// Measured on 27.0 with scripts/panel-lab (`run.sh tap`).
///
/// Only enabled while our panel is on screen. Creating the tap needs Accessibility, which
/// the app has whenever it can read the panel at all.
@MainActor
final class PanelClickRouter {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private weak var window: NSWindow?
    /// More windows of ours whose clicks Notification Center mustn't see either while the
    /// panel is up: Settings, so its panel stays open while its place is dragged there.
    var otherWindows: () -> [NSWindow] = { [] }
    /// The window a click that started in one of ours goes to, from mouse down to mouse
    /// up: its drag and release go there too, wherever they happen.
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

    /// Starts routing clicks inside `window`. Returns false if the tap can't be created,
    /// in which case the caller must not take over: the first click would close the panel.
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
        if type == .leftMouseDown, ProcessInfo.processInfo.environment["NN_TIMING"] == "1" { // DEBUG-CLICK
            FileHandle.standardError.write(Data("[router] down seen, panel visible=\(window?.isVisible ?? false) pass=\(passThrough) uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
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
        // Not from inside the tap callback: a slow handler there would get the tap disabled.
        if window === panel {
            if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" { // DEBUG-CLICK
                FileHandle.standardError.write(Data("[router] \(ns.type.rawValue) to panel at \(ns.locationInWindow) uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
            }
            DispatchQueue.main.async { [weak window] in window?.sendEvent(ns) }
        } else {
            // Settings isn't the key window while Notification Center's panel is open, and
            // a window that isn't key spends a click on becoming key, which it can't then:
            // dragging the panel's place there did nothing. The view under the pointer gets
            // the events directly instead, as a key window would hand them on.
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

    /// The one of `windows` that is frontmost at `point`, if it is the frontmost window of
    /// any app there: a click on another app's window over ours is that app's.
    private static func window(at point: NSPoint, among windows: [NSWindow]) -> NSWindow? {
        let front = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        return windows.first { $0.isVisible && $0.windowNumber == front && $0.frame.contains(point) }
    }

    /// Event taps use the global top-left origin of the main display, AppKit the bottom-left.
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
