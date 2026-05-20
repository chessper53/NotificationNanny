import AppKit
import CoreGraphics

/// Per-screen notification placement: which corner + a fine-tune nudge.
package struct ScreenPlacement: Codable, Equatable {
    package var position: NotificationPosition
    package var xOffset: Double
    package var yOffset: Double

    package static let `default` = ScreenPlacement(position: .topRight, xOffset: 0, yOffset: 0)
}

extension NSScreen {
    /// Stable identifier for a physical display. Survives sleep/wake; if you
    /// disconnect & reconnect the same monitor you usually get the same ID
    /// back (depends on the GPU driver).
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = deviceDescription[key] as? NSNumber else { return 0 }
        return CGDirectDisplayID(value.uint32Value)
    }

    /// Human-readable name to show in the picker.
    var nannyDisplayName: String {
        if #available(macOS 14, *), !localizedName.isEmpty {
            return localizedName
        }
        if let index = NSScreen.screens.firstIndex(of: self) {
            return "Display \(index + 1)"
        }
        return "Display \(displayID)"
    }
}
