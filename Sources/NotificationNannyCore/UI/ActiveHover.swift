import AppKit
import SwiftUI

/// Hover that works in windows of an app that isn't active.
///
/// NotificationNanny's banners and panel never activate the app: that would take the
/// focus from whatever you are working in, and from Notification Center, whose panel then
/// closes. SwiftUI's `onHover` doesn't report then, and neither does an AppKit tracking
/// area, even one that is always active (measured on 27.0, scripts/panel-lab
/// `hover-test`). Where the pointer is can always be read, so this reads it.
private struct ActiveHoverArea: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> HoverView {
        let view = HoverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: HoverView, context: Context) {
        view.onChange = onChange
    }
}

@MainActor
final class HoverView: NSView {
    var onChange: ((Bool) -> Void)?
    private var inside = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { PointerWatcher.shared.add(self) } else { PointerWatcher.shared.remove(self) }
    }

    // Only watches; clicks go to the views on top.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    fileprivate func check(_ pointer: NSPoint) {
        guard let window else { return }
        let now = window.isVisible && window.alphaValue > 0
            && window.convertToScreen(convert(bounds, to: nil)).contains(pointer)
        guard now != inside else { return }
        inside = now
        onChange?(now)
    }
}

/// One timer for every hover area on screen, running only while there is one.
@MainActor
private final class PointerWatcher {
    static let shared = PointerWatcher()
    private let views = NSHashTable<HoverView>.weakObjects()
    private var timer: Timer?

    func add(_ view: HoverView) {
        views.add(view)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { PointerWatcher.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func remove(_ view: HoverView) {
        views.remove(view)
        if views.allObjects.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        let pointer = NSEvent.mouseLocation
        for view in views.allObjects { view.check(pointer) }
    }
}

extension View {
    /// Like `onHover`, but also while NotificationNanny isn't the active app.
    func activeHover(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(ActiveHoverArea(onChange: onChange))
    }
}
