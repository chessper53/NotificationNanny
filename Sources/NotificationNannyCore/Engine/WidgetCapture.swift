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
    /// Captures the part of `windowID` with the rects and cuts out each, given in points from
    /// the window's top left.
    func capture(windowID: CGWindowID, rects: [String: CGRect]) async -> [String: NSImage] {
        guard !rects.isEmpty else { return [:] }
        if let cached, cached.windowID == windowID {
            let images = await capture(cached, rects: rects)
            if !images.isEmpty { return images }
        }
        // Finding the window means listing every window there is, which took most of a
        // capture's time; it is done once for Notification Center's, and again only when
        // that one stops capturing.
        cached = nil
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return [:] }
        cached = window
        return await capture(window, rects: rects)
    }

    private var cached: SCWindow?

    /// A picture of nothing: one colour all over. A window caught while it is moved, or
    /// a widget while it redraws at another size, captures so, and it replaced the
    /// widget's picture with an empty box. Every widget draws something.
    nonisolated static func isBlank(_ image: CGImage) -> Bool {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let values = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2]) }
        return (values.max() ?? 0) - (values.min() ?? 0) < 12
    }

    private func capture(_ window: SCWindow, rects: [String: CGRect]) async -> [String: NSImage] {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        // Only where the widgets are: the whole window is the screen's size, and a picture
        // of all of it took some 170 ms every 2 s.
        let area = rects.values.dropFirst().reduce(rects.values.first!) { $0.union($1) }.integral
        let config = SCStreamConfiguration()
        config.sourceRect = area
        config.width = Int(area.width * scale)
        config.height = Int(area.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        else { return [:] }
        var result: [String: NSImage] = [:]
        for (id, rect) in rects {
            let pixels = CGRect(x: (rect.minX - area.minX) * scale, y: (rect.minY - area.minY) * scale,
                                width: rect.width * scale, height: rect.height * scale).integral
            guard let part = image.cropping(to: pixels), !Self.isBlank(part) else { continue }
            result[id] = NSImage(cgImage: part, size: rect.size)
        }
        return result
    }
}
