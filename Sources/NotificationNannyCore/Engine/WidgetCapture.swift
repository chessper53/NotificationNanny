import AppKit
@preconcurrency import ScreenCaptureKit

/// Captures native panel widgets for the custom panel. Requires Screen Recording.
/// Keep part of the host on screen so widgets continue rendering; see NCPanelTakeover.
@MainActor
final class WidgetCapture {
    /// Captures rectangles in points from the native window's top left corner.
    func capture(windowID: CGWindowID, rects: [String: CGRect]) async -> [String: NSImage] {
        guard !rects.isEmpty else { return [:] }
        if let cached, cached.windowID == windowID {
            let images = await capture(cached, rects: rects)
            if !images.isEmpty { return images }
        }
        // Reuse the window lookup until capture fails to avoid listing every system window each
        // time.
        cached = nil
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return [:] }
        cached = window
        return await capture(window, rects: rects)
    }

    private var cached: SCWindow?

    /// Reject nearly uniform captures taken while a window moves or a widget redraws.
    nonisolated static func isBlank(_ image: CGImage) -> Bool {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        // Draw within the buffer's lifetime; the pointer passed to CGContext must remain valid
        // until drawing ends.
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        // Split the calculation to keep type checking fast across compiler versions.
        var lowest = Int.max
        var highest = Int.min
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[i])
            let green = Int(pixels[i + 1])
            let blue = Int(pixels[i + 2])
            let sum: Int = red + green + blue
            lowest = min(lowest, sum)
            highest = max(highest, sum)
        }
        return highest - lowest < 12
    }

    private func capture(_ window: SCWindow, rects: [String: CGRect]) async -> [String: NSImage] {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        // Capture the widget bounds only; the fullscreen host is much larger.
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
