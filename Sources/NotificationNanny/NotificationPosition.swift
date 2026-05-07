import AppKit
import CoreGraphics
import SwiftUI

enum NotificationPosition: String, CaseIterable, Identifiable, Codable {
    case topLeft, topCenter, topRight
    case middleLeft, middleCenter, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft:      return "Top Left"
        case .topCenter:    return "Top Center"
        case .topRight:     return "Top Right"
        case .middleLeft:   return "Middle Left"
        case .middleCenter: return "Middle Center"
        case .middleRight:  return "Middle Right"
        case .bottomLeft:   return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight:  return "Bottom Right"
        }
    }

    /// SwiftUI alignment used to render the indicator dot inside a position-grid tile.
    var alignment: Alignment {
        switch self {
        case .topLeft:      return .topLeading
        case .topCenter:    return .top
        case .topRight:     return .topTrailing
        case .middleLeft:   return .leading
        case .middleCenter: return .center
        case .middleRight:  return .trailing
        case .bottomLeft:   return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight:  return .bottomTrailing
        }
    }

    var stacksUpward: Bool {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight: return true
        default: return false
        }
    }

    /// Built-in inset from the visible frame so default positions don't kiss the screen edge.
    private static let safeInset: CGFloat = 8

    /// Compute the desired window origin in **Accessibility coordinates**
    /// (origin top-left of the *primary* screen, y increases downward).
    /// Caller passes the screen that the notification is currently on.
    func axOrigin(forWindowSize windowSize: CGSize,
                  screen: NSScreen,
                  xOffset: CGFloat,
                  yOffset: CGFloat) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        let inset = Self.safeInset

        let axTop    = primaryHeight - visible.maxY + inset
        let axBottom = primaryHeight - visible.minY - inset
        let axLeft   = visible.minX + inset
        let axRight  = visible.maxX - inset

        let x: CGFloat
        switch self {
        case .topLeft, .middleLeft, .bottomLeft:
            x = axLeft
        case .topCenter, .middleCenter, .bottomCenter:
            x = axLeft + ((axRight - axLeft) - windowSize.width) / 2
        case .topRight, .middleRight, .bottomRight:
            x = axRight - windowSize.width
        }

        let y: CGFloat
        switch self {
        case .topLeft, .topCenter, .topRight:
            y = axTop
        case .middleLeft, .middleCenter, .middleRight:
            y = axTop + ((axBottom - axTop) - windowSize.height) / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = axBottom - windowSize.height
        }

        return CGPoint(x: x + xOffset, y: y + yOffset)
    }
}
