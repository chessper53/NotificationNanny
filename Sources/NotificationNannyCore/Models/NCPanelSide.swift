import Foundation

/// Which side of the screen the custom Notification Center opens on. The system's is on
/// the right.
package enum NCPanelSide: String, Codable, CaseIterable, Identifiable {
    case right, left
    package var id: String { rawValue }
    /// The Settings label, a key of Localizable.strings.
    package var labelKey: String { self == .right ? "Right" : "Left" }
}
