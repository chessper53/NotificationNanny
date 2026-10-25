import AppKit
@preconcurrency import ScreenCaptureKit

/// Pictures of widgets in Notification Center's panel, for the custom one.
///
/// A widget is drawn by its own app, and Accessibility only describes it, so a picture of
/// the real one is the only way to show it as it looks. A window is only drawn while some
/// of it is on screen, so the panel has to be under ours rather than parked, but covered
/// windows capture fine (measured on 27.0, scripts/panel-lab `widget-cover`). Needs Screen
/// Recording.
@MainActor
final class WidgetCapture {
    /// Captures `windowID` and cuts out each rect, given in points from the window's top left.
    func capture(windowID: CGWindowID, rects: [String: CGRect]) async -> [String: NSImage] {
        guard !rects.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return [:] }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        else { return [:] }
        var result: [String: NSImage] = [:]
        for (id, rect) in rects {
            let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                width: rect.width * scale, height: rect.height * scale).integral
            guard let part = image.cropping(to: pixels) else { continue }
            result[id] = NSImage(cgImage: part, size: rect.size)
        }
        return result
    }
}
