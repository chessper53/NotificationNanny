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

    /// Persistent per-monitor identifier, stable across the `displayID` reassignments
    /// that can happen on sleep/wake or a dock reconnect (same physical panel, new
    /// CGDirectDisplayID). Use this — not `displayID` — as a dictionary/UserDefaults key
    /// for anything that must survive those reassignments. Falls back to a numeric key
    /// derived from `displayID` on the rare display that doesn't vend a UUID.
    var stableDisplayKey: String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "id:\(displayID)"
    }

    /// Short one-line descriptor for the activity log: name, raw displayID, and a short
    /// prefix of the stable key. Comparing these across two consecutive "screen changed"
    /// events reveals a displayID reassignment (same stable key, different displayID) —
    /// the exact signature of the "position reverted to default" bug.
    var nannyLogDescriptor: String {
        let key = stableDisplayKey
        let shortKey = key.hasPrefix("id:") ? key : "uuid:\(key.prefix(8))"
        let f = frame
        return "\(nannyDisplayName) id=\(displayID) \(shortKey) \(Int(f.width))x\(Int(f.height))"
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
