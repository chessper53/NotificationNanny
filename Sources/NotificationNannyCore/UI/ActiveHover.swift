import AppKit
import SwiftUI

/// Poll pointer position for hover in inactive windows; native hover callbacks do not fire there.
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

/// Share one hover timer, running only while an observed window is visible.
@MainActor
private final class PointerWatcher {
    static let shared = PointerWatcher()
    private let views = NSHashTable<HoverView>.weakObjects()
    private var timer: Timer?
    private var shown: NSObjectProtocol?

    private init() {
        shown = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                       object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PointerWatcher.shared.wakeIfNeeded() }
        }
    }

    func add(_ view: HoverView) {
        views.add(view)
        wakeIfNeeded()
    }

    func remove(_ view: HoverView) {
        views.remove(view)
        if views.allObjects.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private var anyShown: Bool { views.allObjects.contains { $0.window?.isVisible == true } }

    private func wakeIfNeeded() {
        guard timer == nil, anyShown else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { PointerWatcher.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let pointer = NSEvent.mouseLocation
        // Once more for those put away, so none of them stays hovered.
        for view in views.allObjects { view.check(pointer) }
        if !anyShown {
            timer?.invalidate()
            timer = nil
        }
    }
}

extension View {
    /// Like `onHover`, but also while NotificationNanny isn't the active app.
    func activeHover(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(ActiveHoverArea(onChange: onChange))
    }
}
