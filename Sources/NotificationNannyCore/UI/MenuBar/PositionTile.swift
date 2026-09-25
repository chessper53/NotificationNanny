import SwiftUI
import AppKit
import UserNotifications

// MARK: - Device chassis

/// Draws the screen preview inside a physical-looking display: a laptop lid and
/// base for the built-in screen, a monitor on a stand for anything external.
///
/// Worth the pixels because it makes a multi-display setup legible at a glance —
/// you recognise which preview is the MacBook without reading the picker — and it
/// frames the preview as "your screen" rather than an abstract grey rectangle.
struct DeviceChrome<Content: View>: View {
    let screen: NSScreen
    let screenSize: CGSize
    @ViewBuilder var content: () -> Content

    private var isLaptop: Bool { CGDisplayIsBuiltin(screen.displayID) != 0 }
    /// Notched Macs report a non-zero top safe area; drawing the notch only when
    /// the real display has one keeps the preview honest.
    private var hasNotch: Bool { screen.safeAreaInsets.top > 0 }

    private var bezel: CGFloat { isLaptop ? 5 : 6 }
    private var chin: CGFloat { isLaptop ? 10 : 16 }

    // Not `static` — DeviceChrome is generic over its content, and generic types
    // can't hold static stored properties.
    private var shell: LinearGradient {
        LinearGradient(colors: [Color(white: 0.42), Color(white: 0.26)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: isLaptop ? 11 : 8, style: .continuous)
                    .fill(shell)
                    .overlay(
                        RoundedRectangle(cornerRadius: isLaptop ? 11 : 8, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
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
        // Sits the whole device on the panel rather than letting it float.
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }

    /// Wedge under the lid, with the finger recess Apple puts on the front edge.
    private var laptopBase: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: screenSize.width + bezel * 2 + 16, height: 9)
            Capsule()
                .fill(Color.black.opacity(0.30))
                .frame(width: screenSize.width * 0.16, height: 3)
                .offset(y: 0.5)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 0.8)
        }
    }

    private var monitorStand: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.22)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 26, height: 12)
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.36), Color(white: 0.22)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: screenSize.width * 0.34, height: 6)
        }
    }
}

// MARK: - Placement editor

/// The device preview, plus a one-line read-out of where the banner sits.
///
/// The offset sliders this replaces were the only control that could push a
/// banner off-screen — they ran to ±the full screen width — and they cost enough
/// width that the preview had to stay small. Dragging on a true-to-scale preview
/// does the same job directly, so the preview gets the space instead.
///
/// Shared by the Position and Exceptions tabs, which previously carried
/// near-identical copies of the fine-tune block.
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

    /// Keeps the numbers the sliders used to show, without giving them a control
    /// that can put the banner somewhere invalid.
    private var offsetSummary: String {
        let x = Int(placement.xOffset.rounded())
        let y = Int(placement.yOffset.rounded())
        return "\(x >= 0 ? "+" : "")\(x), \(y >= 0 ? "+" : "")\(y) px"
    }
}

// MARK: - Shared drag tile

struct DraggableScreenTile: View {
    let screen: NSScreen
    @Binding var placement: ScreenPlacement
    /// Budget for the picture area. The preview is scaled to fit inside this
    /// while keeping the display's real proportions, so it never fills both.
    var maxWidth: CGFloat = 430
    var maxHeight: CGFloat = 280

    private static let realBannerSize = CGSize(width: 372, height: 100)

    var body: some View {
        // The preview shows the whole display, not just the visible frame.
        // Banner placement is measured from the visible frame — which already
        // excludes the menu bar — so drawing a menu bar *inside* a visible-frame
        // preview counted it twice, and a top-anchored banner appeared to sit
        // over the menu bar when in reality it sits below it.
        let frame   = screen.frame
        let visible = screen.visibleFrame
        let menuBarHeight = max(0, frame.maxY - visible.maxY)
        let dockHeight    = max(0, visible.minY - frame.minY)
        let visibleLeft   = visible.minX - frame.minX

        // One scale for both axes. The old code clamped tile height into
        // 100...220 and then compensated with separate x/y scales, which meant
        // the preview was a stretched version of the display and dragging didn't
        // correspond to where the banner actually landed.
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
                Rectangle().fill(Self.wallpaper)
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: menuBarHeight * scale)
                if dockHeight > 2 {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: dockHeight * scale)
                        .offset(y: tileHeight - dockHeight * scale)
                }
                // Drawn without clamping: a config saved with the old sliders can
                // sit partly off-screen, and the preview should show that honestly
                // rather than quietly pretending it's somewhere else.
                BannerChip(width: bannerWidth, height: bannerHeight)
                    .position(x: bannerCenterTile.x, y: bannerCenterTile.y)
            }
            .frame(width: tileWidth, height: tileHeight)
            .clipped()
            .contentShape(Rectangle())
            // Gesture on the ZStack so .local coords = tile coords, not chip-local coords
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        commitDrag(at: value.location, scale: scale, visible: visible,
                                   visibleLeft: visibleLeft, menuBarHeight: menuBarHeight)
                    }
            )
            .onTapGesture { tap in
                commitDrag(at: tap, scale: scale, visible: visible,
                           visibleLeft: visibleLeft, menuBarHeight: menuBarHeight)
            }
        }
    }

    /// Tile point (full-frame, top-left origin) back into visible-frame coords.
    private func commitDrag(at point: CGPoint, scale: CGFloat, visible: CGRect,
                            visibleLeft: CGFloat, menuBarHeight: CGFloat) {
        updatePlacement(visiblePoint: CGPoint(x: point.x / scale - visibleLeft,
                                              y: point.y / scale - menuBarHeight),
                        visible: visible)
    }

    /// Stands in for the desktop picture so the banner chips read as sitting on a
    /// screen rather than floating in an empty box.
    private static let wallpaper = LinearGradient(
        colors: [Color(red: 0.13, green: 0.15, blue: 0.20),
                 Color(red: 0.08, green: 0.09, blue: 0.12)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Banner centre in visible-frame coordinates, top-left origin — the same
    /// frame of reference the repositioner uses when it places the real window.
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

    /// Clamped so a drag can only ever produce an on-screen banner. This is now
    /// the only way to set a placement — the old offset sliders ran to ±the full
    /// screen width, which is how banners ended up off-screen. Existing stored
    /// offsets are left alone; they're only replaced once the user drags.
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

        // One write, not three. Each assignment through the binding is a full
        // get-mutate-set of the placements dictionary — at 60 Hz, writing the
        // three fields separately tripled the JSON encode, the UserDefaults
        // write, and the SwiftUI invalidation for every frame of the drag.
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

// MARK: - Test notification helper

package enum TestNotification {
    /// Sends the test banner and returns its unique title, so the repositioner can tell
    /// this specific banner apart from real notifications that arrive at the same time.
    ///
    /// Prefers `UNUserNotificationCenter` (no subprocess) when the user has granted
    /// notification permission — requested once, silently, at first launch. Falls back
    /// to `osascript`'s `display notification`, which posts under a distinct identity
    /// that doesn't require this app's own notification permission, when the user
    /// hasn't granted (or hasn't yet responded to) that request.
    @discardableResult
    static func send() -> String {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        let title = "Test #\(stamp)"
        dispatch(title: title, body: "Thank you for using NotificationNanny!")
        return title
    }

    /// Fires `count` notifications back-to-back from a single AppleScript run (with a short delay
    /// between each) to reproduce the rapid-succession race. Used by the hidden Debug tab.
    static func sendBurst(count: Int) {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        var lines: [String] = []
        for i in 1...max(1, count) {
            lines.append("display notification \"Back-to-back message \(i) of \(count)\" with title \"Burst #\(stamp)-\(i)\"")
            if i < count { lines.append("delay 0.4") }
        }
        run(script: lines.joined(separator: "\n"))
    }

    /// One real-path notification with an arbitrary title/body — used by the Diagnostics tab to
    /// exercise content extraction (`splitTitleBody`), wrapping, unicode handling, and width logic.
    static func sendCustom(title: String, body: String) {
        dispatch(title: title, body: body)
    }

    /// Escapes a Swift string for safe embedding inside an AppleScript double-quoted literal.
    private static func escapeAS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func dispatch(title: String, body: String) {
        // UNUserNotificationCenter.current() raises when the process has no bundle
        // identifier (unit tests, `swift run`), so take the osascript path there
        // rather than trapping.
        guard Bundle.main.bundleIdentifier != nil else {
            run(script: "display notification \"\(escapeAS(body))\" with title \"\(escapeAS(title))\"")
            return
        }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            var authorized = status == .authorized
            if status == .notDetermined {
                // Only the launch request has asked so far, and it went unanswered.
                // Sending a test is an explicit request for a notification, so ask
                // here: without permission the test goes through osascript, which
                // macOS shows as Script Editor with Script Editor's icon.
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
        Scenario(label: "Comma in sender", title: "Stählin, Caspar",
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
