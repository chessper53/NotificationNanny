import AppKit
import CoreGraphics
import SwiftUI

package enum NotificationPosition: String, CaseIterable, Identifiable, Codable {
    case topLeft, topCenter, topRight
    case middleLeft, middleCenter, middleRight
    case bottomLeft, bottomCenter, bottomRight

    package var id: String { rawValue }

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

    /// Indicator alignment inside a position tile.
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

    /// Inset from the visible screen edge for default placements.
    private static let safeInset: CGFloat = 8

    /// Returns the window origin in AX coordinates: main display top left, y increasing downward.
    /// Use the screen currently containing the notification.
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

    /// Place and clamp the whole pile, growing upward at bottom anchors.
    /// Oversized piles keep their newest banner at the top in view.
    func axStackOrigin(stackSize: CGSize,
                       screen: NSScreen,
                       xOffset: CGFloat,
                       yOffset: CGFloat) -> CGPoint {
        let placed = axOrigin(forWindowSize: stackSize, screen: screen, xOffset: xOffset, yOffset: yOffset)
        return Self.clamp(placed, size: stackSize, into: Self.axVisibleFrame(of: screen))
    }

    /// The screen's visible frame (without menu bar and Dock) in Accessibility coordinates.
    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: primaryHeight - visible.maxY,
                      width: visible.width, height: visible.height)
    }

    /// Clamp to the frame with minimal movement; oversized rectangles keep their top left edge
    /// visible.
    static func clamp(_ origin: CGPoint, size: CGSize, into frame: CGRect) -> CGPoint {
        CGPoint(x: max(min(origin.x, frame.maxX - size.width), frame.minX),
                y: max(min(origin.y, frame.maxY - size.height), frame.minY))
    }
}
