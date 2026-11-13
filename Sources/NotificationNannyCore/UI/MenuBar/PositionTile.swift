import SwiftUI
import AppKit
import UserNotifications

// MARK: Preview colours

/// Appearance aware screen preview colors.
enum ScreenPreview {
    /// A grey, at `dark` in Dark and `light` in Light.
    static func tone(_ dark: CGFloat, light: CGFloat, alpha: CGFloat = 1) -> Color {
        Color.nannyAdaptive(light: NSColor(white: light, alpha: alpha), dark: NSColor(white: dark, alpha: alpha))
    }

    /// From one grey to another in Dark; one flat grey in Light.
    static func shade(_ top: CGFloat, _ bottom: CGFloat, light: CGFloat,
                      start: UnitPoint = .top, end: UnitPoint = .bottom) -> LinearGradient {
        LinearGradient(colors: [tone(top, light: light), tone(bottom, light: light)], startPoint: start, endPoint: end)
    }

    /// Desktop backdrop for the screen preview.
    static let wallpaper = LinearGradient(
        colors: [Color.nannyAdaptive(light: NSColor(srgbRed: 0.87, green: 0.89, blue: 0.93, alpha: 1),
                                     dark: NSColor(srgbRed: 0.13, green: 0.15, blue: 0.20, alpha: 1)),
                 Color.nannyAdaptive(light: NSColor(srgbRed: 0.87, green: 0.89, blue: 0.93, alpha: 1),
                                     dark: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 1))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let menuBar = Color.nannyAdaptive(light: .white.withAlphaComponent(0.8), dark: .white.withAlphaComponent(0.16))
    static let dock = Color.nannyAdaptive(light: .black.withAlphaComponent(0.07), dark: .white.withAlphaComponent(0.10))
    /// The device's edge highlight, and its shadow on the card.
    static let edge = Color.nannyAdaptive(light: .black.withAlphaComponent(0.14), dark: .white.withAlphaComponent(0.22))
    static let shadow = Color.nannyAdaptive(light: .black.withAlphaComponent(0.12), dark: .black.withAlphaComponent(0.45))
}

// MARK: Device chassis

/// Distinguish the internal laptop display from external monitors in screen previews.
struct DeviceChrome<Content: View>: View {
    let screen: NSScreen
    let screenSize: CGSize
    @ViewBuilder var content: () -> Content

    private var isLaptop: Bool { CGDisplayIsBuiltin(screen.displayID) != 0 }
    /// Draw a notch only when the real display reports one.
    private var hasNotch: Bool { screen.safeAreaInsets.top > 0 }

    private var bezel: CGFloat { isLaptop ? 5 : 6 }
    private var chin: CGFloat { isLaptop ? 10 : 16 }

    // Generic types cannot have static stored properties.
    private var shell: LinearGradient {
        ScreenPreview.shade(0.42, 0.26, light: 0.84)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: isLaptop ? 11 : 8, style: .continuous)
                    .fill(shell)
                    .overlay(
                        RoundedRectangle(cornerRadius: isLaptop ? 11 : 8, style: .continuous)
                            .stroke(ScreenPreview.edge, lineWidth: 0.8)
                    )
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        content()
                            .clipShape(RoundedRectangle(cornerRadius: isLaptop ? 5 : 3,
                                                        style: .continuous))
                        if hasNotch {
                            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3,
                                                   style: .continuous)
                                .fill(Color.black)
                                .frame(width: screenSize.width * 0.17, height: 6)
                        }
                    }
                    if !isLaptop {
                        // Monitors carry their logo area below the glass.
                        Spacer(minLength: 0).frame(height: chin - bezel)
                    }
                }
                .padding(bezel)
            }
            .frame(width: screenSize.width + bezel * 2,
                   height: screenSize.height + bezel * 2 + (isLaptop ? 0 : chin - bezel))

            if isLaptop { laptopBase } else { monitorStand }
        }
        .shadow(color: ScreenPreview.shadow, radius: 6, y: 3)
    }

    /// Wedge under the lid, with the finger recess Apple puts on the front edge.
    private var laptopBase: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
                .fill(ScreenPreview.shade(0.34, 0.20, light: 0.78))
                .frame(width: screenSize.width + bezel * 2 + 16, height: 9)
            Capsule()
                .fill(ScreenPreview.tone(0, light: 0, alpha: 0.18))
                .frame(width: screenSize.width * 0.16, height: 3)
                .offset(y: 0.5)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(ScreenPreview.tone(1, light: 1, alpha: 0.18)).frame(height: 0.8)
        }
    }

    private var monitorStand: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ScreenPreview.shade(0.30, 0.22, light: 0.76, start: .leading, end: .trailing))
                .frame(width: 26, height: 12)
            Capsule()
                .fill(ScreenPreview.shade(0.36, 0.22, light: 0.80))
                .frame(width: screenSize.width * 0.34, height: 6)
        }
    }
}

// MARK: Placement editor

/// Shared display preview and placement editor for Position and Exceptions.
struct PlacementEditor: View {
    let screen: NSScreen
    @Binding var placement: ScreenPlacement
    var maxWidth: CGFloat = 430
    var maxHeight: CGFloat = 280

    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        let isDefault = placement.xOffset == 0 && placement.yOffset == 0

        VStack(spacing: 7) {
            DraggableScreenTile(screen: screen, placement: $placement,
                                maxWidth: maxWidth, maxHeight: maxHeight)

            HStack(spacing: 6) {
                LocalizedText(placement.position.label)
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if !isDefault {
                    Text(offsetSummary)
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(loc.string("Reset")) {
                    placement.xOffset = 0
                    placement.yOffset = 0
                }
                .buttonStyle(.borderless).font(.caption)
                .foregroundStyle(Color.nannyAccent).disabled(isDefault)
            }
            .frame(maxWidth: maxWidth)
        }
        .frame(maxWidth: .infinity)
    }

    /// Readout of the current placement offsets.
    private var offsetSummary: String {
        let x = Int(placement.xOffset.rounded())
        let y = Int(placement.yOffset.rounded())
        return "\(x >= 0 ? "+" : "")\(x), \(y >= 0 ? "+" : "")\(y) px"
    }
}

// MARK: Shared drag tile

struct DraggableScreenTile: View {
    let screen: NSScreen
    @Binding var placement: ScreenPlacement
    /// Fit the preview inside these bounds while preserving display proportions.
    var maxWidth: CGFloat = 430
    var maxHeight: CGFloat = 280

    /// Pointer offset from the banner center, preventing a jump when dragging starts.
    @State private var grab: CGSize?

    private static let realBannerSize = CGSize(width: 372, height: 100)

    var body: some View {
        // Preview the full display; placement uses the visible frame that already excludes the menu
        // bar.
        let frame   = screen.frame
        let visible = screen.visibleFrame
        let menuBarHeight = max(0, frame.maxY - visible.maxY)
        let dockHeight    = max(0, visible.minY - frame.minY)
        let visibleLeft   = visible.minX - frame.minX

        // Use one scale for both axes so dragging matches the real display.
        let scale = min(maxWidth / max(frame.width, 1),
                        maxHeight / max(frame.height, 1))
        let tileWidth  = frame.width  * scale
        let tileHeight = frame.height * scale
        let bannerWidth  = Self.realBannerSize.width  * scale
        let bannerHeight = Self.realBannerSize.height * scale

        let centreInVisible = bannerCentreInVisible(visible: visible)
        let bannerCenterTile = CGPoint(
            x: (visibleLeft + centreInVisible.x) * scale,
            y: (menuBarHeight + centreInVisible.y) * scale
        )

        return DeviceChrome(screen: screen,
                            screenSize: CGSize(width: tileWidth, height: tileHeight)) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(ScreenPreview.wallpaper)
                Rectangle()
                    .fill(ScreenPreview.menuBar)
                    .frame(height: menuBarHeight * scale)
                if dockHeight > 2 {
                    Rectangle()
                        .fill(ScreenPreview.dock)
                        .frame(height: dockHeight * scale)
                        .offset(y: tileHeight - dockHeight * scale)
                }
                // Show legacy offsets as saved, even when they place the banner partly off screen.
                BannerChip(width: bannerWidth, height: bannerHeight)
                    .position(x: bannerCenterTile.x, y: bannerCenterTile.y)
            }
            .frame(width: tileWidth, height: tileHeight)
            .clipped()
            .contentShape(Rectangle())
            // Attach to the stack so gesture coordinates use the tile, not the banner chip.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let chip = CGRect(x: bannerCenterTile.x - bannerWidth / 2,
                                          y: bannerCenterTile.y - bannerHeight / 2,
                                          width: bannerWidth, height: bannerHeight)
                        let start = value.startLocation
                        let hold = grab ?? (chip.contains(start)
                            ? CGSize(width: start.x - bannerCenterTile.x, height: start.y - bannerCenterTile.y)
                            : .zero)
                        if grab == nil { grab = hold }
                        commitDrag(at: CGPoint(x: value.location.x - hold.width, y: value.location.y - hold.height),
                                   scale: scale, visible: visible,
                                   visibleLeft: visibleLeft, menuBarHeight: menuBarHeight)
                    }
                    .onEnded { _ in grab = nil }
            )
            .onTapGesture { tap in
                commitDrag(at: tap, scale: scale, visible: visible,
                           visibleLeft: visibleLeft, menuBarHeight: menuBarHeight)
            }
        }
    }

    /// Convert tile coordinates to the visible frame with a top left origin.
    private func commitDrag(at point: CGPoint, scale: CGFloat, visible: CGRect,
                            visibleLeft: CGFloat, menuBarHeight: CGFloat) {
        updatePlacement(visiblePoint: CGPoint(x: point.x / scale - visibleLeft,
                                              y: point.y / scale - menuBarHeight),
                        visible: visible)
    }


    /// Banner center in visible frame coordinates, matching the repositioner.
    private func bannerCentreInVisible(visible: CGRect) -> CGPoint {
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
        return CGPoint(x: x + banner.width / 2 + CGFloat(placement.xOffset),
                       y: y + banner.height / 2 + CGFloat(placement.yOffset))
    }

    /// Clamp new drags to the visible frame; do not rewrite saved offsets until the user edits
    /// them.
    private func updatePlacement(visiblePoint point: CGPoint, visible: CGRect) {
        let banner = Self.realBannerSize
        let inset: CGFloat = 8
        let centreX = max(inset + banner.width / 2,
                          min(visible.width  - inset - banner.width  / 2, point.x))
        let centreY = max(inset + banner.height / 2,
                          min(visible.height - inset - banner.height / 2, point.y))

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

        // Assign once per drag update to avoid repeated publications of the placement dictionary.
        var updated = placement
        updated.position = anchor
        updated.xOffset  = Double(centreX - refX)
        updated.yOffset  = Double(centreY - refY)
        guard updated != placement else { return }
        placement = updated
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

// MARK: Test notification helper

package enum TestNotification {
    /// Returns a unique test title to distinguish concurrent real notifications.
    /// Uses native notifications when allowed, with osascript as the permission fallback.
    @discardableResult
    static func send() -> String {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        let title = "Test #\(stamp)"
        dispatch(title: title, body: "Thank you for using NotificationNanny!")
        return title
    }

    /// Posts a short burst to exercise rapid notification races from Diagnostics.
    static func sendBurst(count: Int) {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        var lines: [String] = []
        for i in 1...max(1, count) {
            lines.append("display notification \"Back-to-back message \(i) of \(count)\" with title \"Burst #\(stamp)-\(i)\"")
            if i < count { lines.append("delay 0.4") }
        }
        run(script: lines.joined(separator: "\n"))
    }

    /// Posts arbitrary content through the normal path to exercise extraction and layout.
    static func sendCustom(title: String, body: String) {
        dispatch(title: title, body: body)
    }

    /// Escapes a string for an AppleScript quoted literal.
    private static func escapeAS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func dispatch(title: String, body: String) {
        // Native notifications require a bundle identifier; tests and swift run must use osascript.
        guard Bundle.main.bundleIdentifier != nil else {
            run(script: "display notification \"\(escapeAS(body))\" with title \"\(escapeAS(title))\"")
            return
        }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            var authorized = status == .authorized
            if status == .notDetermined {
                // A user requested a test; ask now if the initial permission request is still
                // unanswered.
                authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            }
            guard authorized else {
                NannyLogger.shared.log("TestNotification: no notification permission, sent via osascript (shows as Script Editor)")
                run(script: "display notification \"\(escapeAS(body))\" with title \"\(escapeAS(title))\"")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
                NannyLogger.shared.log("TestNotification: delivered via UNUserNotificationCenter")
            } catch {
                NannyLogger.shared.log("TestNotification: UNUserNotificationCenter failed (\(error.localizedDescription)) — falling back to osascript", level: .warn)
                run(script: "display notification \"\(escapeAS(body))\" with title \"\(escapeAS(title))\"")
            }
        }
    }

    /// Tricky notification shapes that have historically broken extraction or layout.
    package struct Scenario: Identifiable {
        package let id = UUID()
        package let label: String
        let title: String
        let body: String
    }

    package static let scenarios: [Scenario] = [
        Scenario(label: "Long message", title: "NotificationNanny",
                 body: "This is a deliberately long notification body to exercise text wrapping, the two-line clamp, and width handling in the custom overlay renderer so overflow is easy to see."),
        Scenario(label: "Comma in sender", title: "Doe, Jane",
                 body: "Tests the comma-containing title split that broke Teams-style senders."),
        Scenario(label: "Title only (no body)", title: "Reminder: stand up and stretch", body: ""),
        Scenario(label: "Emoji & unicode", title: "Café ☕️ 你好 🎉",
                 body: "Accents éàü, emoji 🔥✅🚀, and a long tail to nudge wrapping."),
        Scenario(label: "Unbroken long word", title: "Link",
                 body: "https://example.com/some/really/long/path/that/will/not/wrap/nicely/segment/end"),
    ]

    private static func run(script: String) {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let errPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errPipe
        task.terminationHandler = { t in
            let code = t.terminationStatus
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                if code != 0 || !errStr.isEmpty {
                    NannyLogger.shared.log("TestNotification: osascript exit=\(code) err=\(errStr)", level: .warn)
                } else {
                    NannyLogger.shared.log("TestNotification: osascript ok")
                }
            }
        }
        do {
            try task.run()
        } catch {
            Task { @MainActor in
                NannyLogger.shared.log("TestNotification: failed to launch osascript: \(error)", level: .error)
            }
        }
    }
}
