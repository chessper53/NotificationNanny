import AppKit
import CoreGraphics

/// Notification anchor and offsets for one screen.
package struct ScreenPlacement: Codable, Equatable {
    package var position: NotificationPosition
    package var xOffset: Double
    package var yOffset: Double

    package static let `default` = ScreenPlacement(position: .topRight, xOffset: 0, yOffset: 0)
}

extension NSScreen {
    /// Current numeric display ID; it can change after sleep or reconnection.
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = deviceDescription[key] as? NSNumber else { return 0 }
        return CGDirectDisplayID(value.uint32Value)
    }

    /// Persistent display key for saved placement, surviving numeric ID reassignment.
    /// Falls back to a numeric key when the display provides no UUID.
    var stableDisplayKey: String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "id:\(displayID)"
    }

    /// Log the name, numeric ID, and stable key prefix to reveal numeric ID reassignment.
    var nannyLogDescriptor: String {
        let key = stableDisplayKey
        let shortKey = key.hasPrefix("id:") ? key : "uuid:\(key.prefix(8))"
        let f = frame
        return "\(nannyDisplayName) id=\(displayID) \(shortKey) \(Int(f.width))x\(Int(f.height))"
    }

    /// Display name for the screen picker.
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
