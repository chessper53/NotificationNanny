import AppKit
import QuartzCore
@preconcurrency import ScreenCaptureKit

/// Masks the native widget menu with a screen capture excluding this app.
/// Keep our panel above the mask so it remains interactive. Requires Screen Recording.
@MainActor
final class ScreenFreeze {
    private var window: NSPanel?
    /// Cache display and app discovery to avoid listing shareable content for every capture.
    private var cached: (display: SCDisplay, us: [SCRunningApplication])?

    /// Menus' level and the two above it: the picture, then our panel.
    static let pictureLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
    static let panelLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)

    /// Capture an AppKit screen rectangle excluding this app; nil if unavailable.
    func take(_ rect: NSRect, on screen: NSScreen) async -> CGImage? {
        await capture(rect, on: screen)
    }

    /// Wait until the mask is on screen; raise any content that must remain above it first.
    func show(_ image: CGImage, over rect: NSRect) async {
        let panel = window ?? Self.makeWindow()
        window = panel
        panel.setFrame(rect, display: false)
        (panel.contentView as? NSImageView)?.image = NSImage(cgImage: image, size: rect.size)
        panel.orderFrontRegardless()
        // Draw now and allow two compositor frames before opening the native menu.
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
        // Disable default panel animations so the mask appears and disappears without exposing
        // native content.
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSImageView()
        view.imageScaling = .scaleAxesIndependently
        panel.contentView = view
        return panel
    }
}
