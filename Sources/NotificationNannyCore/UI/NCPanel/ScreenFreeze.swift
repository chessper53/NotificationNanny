import AppKit
import QuartzCore
@preconcurrency import ScreenCaptureKit

/// A picture of part of a screen, without this app's windows, held over it for a moment.
///
/// A widget's menu can only be had from Notification Center's own, which it opens on a
/// screen wherever its panel is, with the widget lifted beside it: a quarter of a second
/// of both on screen each time (filmed on 27.0). Above them, at the level just over menus,
/// this shows what was there before, and our panel goes one higher, so it stays live on
/// top of it. Needs Screen Recording, which widgets need anyway.
@MainActor
final class ScreenFreeze {
    private var window: NSPanel?
    /// The shareable display and this app, found once: listing them took most of a capture.
    private var cached: (display: SCDisplay, us: [SCRunningApplication])?

    /// Menus' level and the two above it: the picture, then our panel.
    static let pictureLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
    static let panelLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)

    /// A picture of `rect` (AppKit coordinates, within `screen`) as it is now, without this
    /// app's windows; nil when there is none to be had.
    func take(_ rect: NSRect, on screen: NSScreen) async -> CGImage? {
        await capture(rect, on: screen)
    }

    /// Puts `image` over `rect` and waits until it is on screen. Raise what has to stay on
    /// top first: the picture covers everything below its level.
    func show(_ image: CGImage, over rect: NSRect) async {
        let panel = window ?? Self.makeWindow()
        window = panel
        panel.setFrame(rect, display: false)
        (panel.contentView as? NSImageView)?.image = NSImage(cgImage: image, size: rect.size)
        panel.orderFrontRegardless()
        // On screen only once drawn and composited: the real menu, opened straight after,
        // came up first, some 50 ms before the picture (sampled from the window list). Drawn
        // now, and two frames given to the window server.
        panel.displayIfNeeded()
        CATransaction.flush()
        try? await Task.sleep(nanoseconds: 40_000_000)
    }

    func hide() { window?.orderOut(nil) }

    private func capture(_ rect: NSRect, on screen: NSScreen) async -> CGImage? {
        for attempt in 0..<2 {
            if cached?.display.displayID != screen.displayID || attempt == 1 {
                guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                      let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { return nil }
                let pid = ProcessInfo.processInfo.processIdentifier
                cached = (display, content.applications.filter { $0.processID == pid })
            }
            guard let cached else { return nil }
            let filter = SCContentFilter(display: cached.display, excludingApplications: cached.us, exceptingWindows: [])
            let config = SCStreamConfiguration()
            // The display's own points, from its top left.
            config.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                       width: rect.width, height: rect.height)
            config.width = Int(rect.width * screen.backingScaleFactor)
            config.height = Int(rect.height * screen.backingScaleFactor)
            config.showsCursor = false
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                return image
            }
        }
        return nil
    }

    private static func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = pictureLevel
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // A panel fades and zooms in and out by default: in, it was a fifth of a second
        // small and see-through with the real menu already up; out, it shrank away over
        // our panel, back at its own level by then.
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSImageView()
        view.imageScaling = .scaleAxesIndependently
        panel.contentView = view
        return panel
    }
}
