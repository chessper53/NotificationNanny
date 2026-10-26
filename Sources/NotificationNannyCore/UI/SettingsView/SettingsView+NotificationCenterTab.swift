import AppKit
import SwiftUI

/// The custom Notification Center's settings, laid out like the Banner tab: one card per
/// setting, its title on top, a note under it. Everything starts as macOS has it; colours
/// start as the banners', and the extras that macOS doesn't have start off.
struct NotificationCenterTabView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var permission = ScreenRecordingPermission.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var previewReplay = 0

    private var screens: [NSScreen] { NSScreen.screens }

    /// The display the preview shows: the chosen one, or while it opens wherever the clock
    /// is clicked, the one Settings is on, drawn as that laptop or monitor.
    private var previewScreen: NSScreen {
        screens.first { $0.displayID == settings.customNotificationCenterDisplayID } ?? NSScreen.main ?? screens[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            mainCard
            if settings.customNotificationCenter {
                positionCard
                sizeCard
                backgroundCard
                textCard
                animationCard
                extrasCard

                Button { NCPanelTakeover.pressMenuBarClock() } label: {
                    Label {
                        LocalizedText("Open Notification Center")
                    } icon: {
                        Image(systemName: "rectangle.rightthird.inset.filled")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nannyProminent).controlSize(.regular)
            }
        }
        .onAppear { permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
        }
    }

    // MARK: - The switch, and widgets under it

    private var mainCard: some View {
        SettingsCard {
            SettingsToggleRow("Use NotificationNanny's Notification Center (experimental)",
                              isOn: $settings.customNotificationCenter)
            SettingsNote("NotificationNanny can show its own list when you click the clock, in place of the Notification Center panel. Your notifications stay in Notification Center: this is another view of them, and everything you do in it goes back there.")

            if settings.customNotificationCenter {
                Divider()
                SettingsToggleRow("Show widgets", isOn: Binding(
                    get: { settings.customNotificationCenterWidgets },
                    set: { on in
                        settings.customNotificationCenterWidgets = on
                        if on, !permission.isGranted { permission.request() }
                    }
                ))
                .padding(.leading, 12)
                SettingsNote("Widgets are drawn by their own apps, so NotificationNanny can only show them as live pictures of the real ones. That needs Screen Recording. Leave this off and widgets are simply left out.")
                    .padding(.leading, 12)
                if settings.customNotificationCenterWidgets { permissionRow.padding(.leading, 12) }
            }
        }
    }

    private var permissionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(permission.isGranted ? Color.nannyAccent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                LocalizedText(permission.isGranted ? "Screen Recording is allowed" : "Screen Recording isn't allowed yet")
                    .font(.callout)
                if !permission.isGranted {
                    SettingsNote("Allow NotificationNanny in System Settings. If you just did, quit and reopen NotificationNanny: macOS only applies it after a restart.")
                }
            }
            Spacer()
            if !permission.isGranted {
                Button(loc.string("Open System Settings")) { permission.openSystemSettings() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Position

    private var isDefaultPlace: Bool {
        settings.customNotificationCenterSide == .right && settings.customNotificationCenterTopOffset == 0
            && settings.customNotificationCenterXOffset == 0
    }

    private var positionCard: some View {
        SettingsCard {
            SettingsCardHeader(titleKey: "Position") {
                DisplayPicker(selection: $settings.customNotificationCenterDisplayID,
                              resolved: screens.first { $0.displayID == settings.customNotificationCenterDisplayID },
                              zeroLabelKey: "Where you click the clock")
                    .controlSize(.small).fixedSize()
            }
            NCPanelPositionTile(screen: previewScreen,
                                side: $settings.customNotificationCenterSide,
                                topOffset: $settings.customNotificationCenterTopOffset,
                                xOffset: $settings.customNotificationCenterXOffset)
                .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                LocalizedText(settings.customNotificationCenterSide.labelKey)
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if !isDefaultPlace, let offsets = offsetSummary {
                    Text(offsets).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Spacer()
                SettingsTextButton(titleKey: "Reset", disabled: isDefaultPlace) {
                    settings.customNotificationCenterSide = .right
                    settings.customNotificationCenterTopOffset = 0
                    settings.customNotificationCenterXOffset = 0
                }
            }
            SettingsNote(isDefaultPlace && settings.customNotificationCenterDisplayID == 0
                         ? "As macOS. Drag it anywhere on the preview."
                         : "Drag it anywhere on the preview.")
        }
    }

    /// How far it is from its side's place, as the Position tab shows a banner's.
    private var offsetSummary: String? {
        let x = Int(settings.customNotificationCenterXOffset.rounded())
        let y = Int(settings.customNotificationCenterTopOffset.rounded())
        guard x != 0 || y != 0 else { return nil }
        return "\(x >= 0 ? "+" : "")\(x), +\(y) px"
    }

    // MARK: - Size

    private var sizeCard: some View {
        SettingsCard {
            SettingsCardHeader(titleKey: "Size") {
                SettingsTextButton(titleKey: "Reset", disabled: abs(settings.customNotificationCenterScale - 1) < 0.01) {
                    settings.customNotificationCenterScale = 1
                }
            }
            SettingsScaleSlider(value: $settings.customNotificationCenterScale, range: 0.8...1.4)
        }
    }

    // MARK: - Colours, as in the Banner tab, with "Same as banners" first

    private var backgroundCard: some View {
        let own = settings.customNotificationCenterOwnBackground
        let tint = settings.customNotificationCenterTint
        return SettingsCard {
            SettingsCardHeader("Background Color")
            ColorSwatchRow(isDefault: own && tint == nil,
                           current: own ? tint?.color : nil,
                           defaultHelpKey: "No tint: the system's look.",
                           onDefault: {
                               settings.customNotificationCenterOwnBackground = true
                               settings.customNotificationCenterTint = nil
                           },
                           onPick: {
                               settings.customNotificationCenterOwnBackground = true
                               settings.customNotificationCenterTint = SettingsColors.tint(of: $0)
                           }) {
                FollowChip(titleKey: "Same as banners", selected: !own) {
                    settings.customNotificationCenterOwnBackground = false
                }
            }
            SettingsNote(!own ? "Same as your banners, and per app where your exception groups set one."
                         : tint == nil ? "No tint: the system's look." : "One tint for every row.")
        }
    }

    private var textCard: some View {
        let own = settings.customNotificationCenterOwnText
        let tint = settings.customNotificationCenterTextTint
        return SettingsCard {
            SettingsCardHeader("Text Color")
            ColorSwatchRow(isDefault: own && tint == nil,
                           current: own ? tint?.color : nil,
                           showsPresets: false,
                           onDefault: {
                               settings.customNotificationCenterOwnText = true
                               settings.customNotificationCenterTextTint = nil
                           },
                           onPick: {
                               settings.customNotificationCenterOwnText = true
                               settings.customNotificationCenterTextTint = SettingsColors.tint(of: $0)
                           }) {
                FollowChip(titleKey: "Same as banners", selected: !own) {
                    settings.customNotificationCenterOwnText = false
                }
            }
            SettingsNote(!own ? "Same as your banners."
                         : tint == nil ? "Default. Follows system appearance" : "Custom text color active.")
        }
    }

    // MARK: - Animation

    private var animationCard: some View {
        SettingsCard {
            SettingsCardHeader(titleKey: "Animation") {
                CardActionButton.replay { previewReplay &+= 1 }
            }
            AnimationPreviewPane(animation: settings.customNotificationCenterAnimation, replay: previewReplay,
                                 tint: previewTint, textColor: previewTextColor)
                .animationPreviewWell { previewReplay &+= 1 }
            AnimationChipGrid(selected: settings.customNotificationCenterAnimation) {
                settings.customNotificationCenterAnimation = $0
                previewReplay &+= 1
            }
            SettingsNote(settings.customNotificationCenterAnimation == .default
                         ? "As macOS: in from the edge of the screen."
                         : "How it comes in when you click the clock, and goes when it closes.")
        }
    }

    private var previewTint: Color {
        settings.customNotificationCenterOwnBackground
            ? settings.customNotificationCenterTint?.color ?? .clear
            : settings.hasBannerColor ? settings.bannerColor : .clear
    }

    private var previewTextColor: Color {
        (settings.customNotificationCenterOwnText ? settings.customNotificationCenterTextTint?.color
            : settings.effectiveBannerTextColor) ?? .primary
    }

    // MARK: - Extras

    private var extrasCard: some View {
        SettingsCard {
            SettingsCardHeader("Extras")
            SettingsToggleRow("Show when notifications arrived", isOn: $settings.customNotificationCenterTimes)
            SettingsToggleRow("Filter by app", isOn: $settings.customNotificationCenterAppFilter)
            SettingsNote("Not part of macOS's Notification Center, so off unless you turn them on. Times are noted when each banner appears; notifications that came in while NotificationNanny wasn't running have none.")
        }
    }
}

/// The display as a device, as on the Position tab, with Notification Center's column on
/// it at its real size. It goes wherever it is dragged; the third of the screen its
/// middle is in picks the side it is measured from, and so the edge it comes in from.
private struct NCPanelPositionTile: View {
    let screen: NSScreen
    @Binding var side: NCPanelSide
    @Binding var topOffset: Double
    @Binding var xOffset: Double
    var maxWidth: CGFloat = 438
    var maxHeight: CGFloat = 260

    /// Where in the column the pointer took hold of it, so it moves with the pointer
    /// rather than jumping its middle under it.
    @State private var grab: CGSize?

    private static let rowSize = CGSize(width: 344, height: 58)
    private static let rowGap: CGFloat = 6
    private static let rows = 3
    private static var columnHeight: CGFloat { rowSize.height * CGFloat(rows) + rowGap * CGFloat(rows - 1) }
    /// Within this of its side's place, or of the system's height, it settles there.
    private static let magnet: CGFloat = 8

    /// The column's left edge on the screen for a side, before any offset.
    private static func base(_ side: NCPanelSide, width: CGFloat) -> CGFloat {
        switch side {
        case .right: return width - CustomNCPanelController.rightInset - rowSize.width
        case .center: return (width - rowSize.width) / 2
        case .left: return CustomNCPanelController.rightInset
        }
    }

    var body: some View {
        let frame = screen.frame
        let menuBar = max(0, frame.maxY - screen.visibleFrame.maxY)
        let scale = min(maxWidth / max(frame.width, 1), maxHeight / max(frame.height, 1))
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        // Where the panel will really be: clamped as it is when it opens.
        let options = NCPanelOptions(side: side, xOffset: CGFloat(xOffset))
        let x = Self.base(side, width: frame.width)
            + CustomNCPanelController.xOffset(options, on: NSRect(origin: .zero, size: frame.size))
        let y = CustomNCPanelController.topInset + topOffset

        let picture = ZStack(alignment: .topLeading) {
            Rectangle().fill(ScreenPreview.wallpaper)
            Rectangle().fill(ScreenPreview.menuBar).frame(height: menuBar * scale)
            VStack(spacing: Self.rowGap * scale) {
                ForEach(0..<Self.rows, id: \.self) { _ in
                    BannerChip(width: Self.rowSize.width * scale, height: Self.rowSize.height * scale)
                }
            }
            .offset(x: x * scale, y: y * scale)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let column = CGRect(x: x, y: y, width: Self.rowSize.width, height: Self.columnHeight)
                let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                let hold = grab ?? (column.contains(start)
                    ? CGSize(width: start.x - column.minX, height: start.y - column.minY)
                    : CGSize(width: column.width / 2, height: column.height / 2))
                if grab == nil { grab = hold }
                move(left: value.location.x / scale - hold.width, top: value.location.y / scale - hold.height,
                     screen: frame.size)
            }
            .onEnded { _ in grab = nil })

        return DeviceChrome(screen: screen, screenSize: size) { picture }
    }

    /// Puts the column's top left corner as near the point as the screen allows, never
    /// above the system's place or closer to an edge than the system's is to its own.
    private func move(left: CGFloat, top: CGFloat, screen size: CGSize) {
        let edge = CustomNCPanelController.rightInset
        let x = min(max(left, edge), max(edge, size.width - edge - Self.rowSize.width))
        let middle = x + Self.rowSize.width / 2
        let newSide: NCPanelSide = middle < size.width / 3 ? .left : middle < size.width * 2 / 3 ? .center : .right
        var across = (x - Self.base(newSide, width: size.width)).rounded()
        if abs(across) < Self.magnet { across = 0 }

        let limit = max(0, size.height - CustomNCPanelController.topInset - Self.columnHeight - 16)
        var down = min(max(0, top - CustomNCPanelController.topInset), limit).rounded()
        if down < Self.magnet { down = 0 }

        if newSide != side { side = newSide }
        if across != xOffset { xOffset = across }
        if down != topOffset { topOffset = down }
    }
}
