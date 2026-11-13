import Foundation

/// Horizontal panel alignment; the native panel defaults to the right.
package enum NCPanelSide: String, Codable, CaseIterable, Identifiable {
    case right, center, left
    package var id: String { rawValue }
    package var labelKey: String {
        switch self {
        case .right: return "Right"
        case .center: return "Center"
        case .left: return "Left"
        }
    }
}
