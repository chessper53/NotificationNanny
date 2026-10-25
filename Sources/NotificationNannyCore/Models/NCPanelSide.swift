import Foundation

/// Where across the screen the custom Notification Center opens: at either edge or in the
/// middle. The system's is on the right.
package enum NCPanelSide: String, Codable, CaseIterable, Identifiable {
    case right, center, left
    package var id: String { rawValue }
    /// The Settings label, a key of Localizable.strings.
    package var labelKey: String {
        switch self {
        case .right: return "Right"
        case .center: return "Center"
        case .left: return "Left"
        }
    }
}
