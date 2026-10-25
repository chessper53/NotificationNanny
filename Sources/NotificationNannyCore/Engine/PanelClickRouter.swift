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
    /// Set from mouse down to mouse up: the drag and release of a click that started in our
    /// panel go to it too, wherever they happen.
    private var routing = false

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
        routing = false
        window = nil
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }

    /// Whether to swallow `event`; if so it has been handed to our window.
    fileprivate func route(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard let window, window.isVisible else { return false }
        let point = Self.appKitPoint(event.location)
        let isDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
        let isUp = type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp
        if isDown { routing = window.frame.contains(point) }
        guard routing else { return false }
        if isUp { routing = false }

        let inWindow = NSPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        guard let kind = Self.appKitType(type),
              let ns = NSEvent.mouseEvent(
                with: kind, location: inWindow, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: Int(event.getIntegerValueField(.mouseEventClickState)),
                pressure: isUp ? 0 : 1)
        else { return false }
        // Not from inside the tap callback: a slow handler there would get the tap disabled.
        DispatchQueue.main.async { [weak window] in window?.sendEvent(ns) }
        return true
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
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
