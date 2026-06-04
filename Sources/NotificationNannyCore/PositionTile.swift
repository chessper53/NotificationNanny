import SwiftUI
import AppKit

// MARK: - Shared drag tile

struct DraggableScreenTile: View {
    let screen: NSScreen
    @Binding var placement: ScreenPlacement

    private static let realBannerSize = CGSize(width: 372, height: 100)

    var body: some View {
        let visible = screen.visibleFrame
        let aspect = visible.width / max(visible.height, 1)
        let tileWidth: CGFloat = 288
        let tileHeight: CGFloat = min(220, max(100, tileWidth / aspect))
        let scale = tileWidth / visible.width
        let bannerWidth = max(36, Self.realBannerSize.width * scale)
        let bannerHeight = max(14, Self.realBannerSize.height * scale)
        let bannerCenterReal = bannerCenterInVisibleCoords(visible: visible)
        let bannerCenterTile = CGPoint(
            x: (bannerCenterReal.x - visible.minX) * scale,
            y: (bannerCenterReal.y - visible.minY) * scale
        )

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            BannerChip(width: bannerWidth, height: bannerHeight)
                .opacity(0.3)
                .position(
                    x: bannerCenterTile.x,
                    y: bannerCenterTile.y + (placement.position.stacksUpward ? -(bannerHeight + 4) : (bannerHeight + 4))
                )
            BannerChip(width: bannerWidth, height: bannerHeight)
                .position(x: bannerCenterTile.x, y: bannerCenterTile.y)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            updatePlacement(fromTilePoint: value.location,
                                            tileSize: CGSize(width: tileWidth, height: tileHeight),
                                            visible: visible)
                        }
                )
        }
        .frame(width: tileWidth, height: tileHeight)
        .contentShape(Rectangle())
        .onTapGesture { tap in
            updatePlacement(fromTilePoint: tap,
                            tileSize: CGSize(width: tileWidth, height: tileHeight),
                            visible: visible)
        }
    }

    private func bannerCenterInVisibleCoords(visible: CGRect) -> CGPoint {
        let banner = Self.realBannerSize
        let inset: CGFloat = 8
        let x: CGFloat
        switch placement.position {
        case .topLeft, .middleLeft, .bottomLeft:        x = inset
        case .topCenter, .middleCenter, .bottomCenter:  x = (visible.width - banner.width) / 2
        case .topRight, .middleRight, .bottomRight:     x = visible.width - banner.width - inset
        }
        let y: CGFloat
        switch placement.position {
        case .topLeft, .topCenter, .topRight:           y = inset
        case .middleLeft, .middleCenter, .middleRight:  y = (visible.height - banner.height) / 2
        case .bottomLeft, .bottomCenter, .bottomRight:  y = visible.height - banner.height - inset
        }
        let cx = visible.minX + x + banner.width / 2 + CGFloat(placement.xOffset)
        let cy = visible.minY + y + banner.height / 2 + CGFloat(placement.yOffset)
        return CGPoint(x: cx, y: cy)
    }

    private func updatePlacement(fromTilePoint point: CGPoint, tileSize: CGSize, visible: CGRect) {
        let scale = tileSize.width / visible.width
        let banner = Self.realBannerSize
        let inset: CGFloat = 8
        let centreX = max(inset + banner.width / 2,
                          min(visible.width - inset - banner.width / 2, point.x / scale))
        let centreY = max(inset + banner.height / 2,
                          min(visible.height - inset - banner.height / 2, point.y / scale))

        let bandX: AnchorBand
        switch centreX {
        case ..<(visible.width / 3): bandX = .start
        case (visible.width * 2 / 3)...: bandX = .end
        default: bandX = .middle
        }
        let bandY: AnchorBand
        switch centreY {
        case ..<(visible.height / 3): bandY = .start
        case (visible.height * 2 / 3)...: bandY = .end
        default: bandY = .middle
        }

        let anchor = anchorPosition(for: bandX, bandY)
        let refX: CGFloat
        switch bandX {
        case .start:  refX = inset + banner.width / 2
        case .middle: refX = visible.width / 2
        case .end:    refX = visible.width - inset - banner.width / 2
        }
        let refY: CGFloat
        switch bandY {
        case .start:  refY = inset + banner.height / 2
        case .middle: refY = visible.height / 2
        case .end:    refY = visible.height - inset - banner.height / 2
        }

        placement.position = anchor
        placement.xOffset  = Double(centreX - refX)
        placement.yOffset  = Double(centreY - refY)
    }

    private enum AnchorBand { case start, middle, end }

    private func anchorPosition(for x: AnchorBand, _ y: AnchorBand) -> NotificationPosition {
        switch (y, x) {
        case (.start,  .start):  return .topLeft
        case (.start,  .middle): return .topCenter
        case (.start,  .end):    return .topRight
        case (.middle, .start):  return .middleLeft
        case (.middle, .middle): return .middleCenter
        case (.middle, .end):    return .middleRight
        case (.end,    .start):  return .bottomLeft
        case (.end,    .middle): return .bottomCenter
        case (.end,    .end):    return .bottomRight
        }
    }
}

struct BannerChip: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.nannyAccent.opacity(0.85))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.nannyAccent, lineWidth: 1))
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

// MARK: - Test notification helper

enum TestNotification {
    static func send() {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        let script = "display notification \"Thank you for using NotificationNanny!\" with title \"Test #\(stamp)\""
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
    }
}
