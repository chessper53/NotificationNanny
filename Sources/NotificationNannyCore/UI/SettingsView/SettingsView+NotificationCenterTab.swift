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

    /// The display the preview shows: the chosen one, or the main one while it opens
    /// wherever the clock is clicked.
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
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.regular)
            }
        }
        .onAppear { permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
        }
    }

    // MARK: - The switch, and widgets under it

    private var mainCard: some View {
        card {
            HStack {
                LocalizedText("Use NotificationNanny's Notification Center (experimental)").font(.callout)
                Spacer()
                Toggle("", isOn: $settings.customNotificationCenter)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            note("NotificationNanny can show its own list when you click the clock, in place of the Notification Center panel. Your notifications stay in Notification Center: this is another view of them, and everything you do in it goes back there.")

            if settings.customNotificationCenter {
                Divider()
                HStack {
                    LocalizedText("Show widgets").font(.callout)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.customNotificationCenterWidgets },
                        set: { on in
                            settings.customNotificationCenterWidgets = on
                            if on, !permission.isGranted { permission.request() }
                        }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                .padding(.leading, 12)
                note("Widgets are drawn by their own apps, so NotificationNanny can only show them as live pictures of the real ones. That needs Screen Recording. Leave this off and widgets are simply left out.")
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
                    note("Allow NotificationNanny in System Settings. If you just did, quit and reopen NotificationNanny: macOS only applies it after a restart.")
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

    private var positionCard: some View {
        let isDefault = settings.customNotificationCenterSide == .right && settings.customNotificationCenterTopOffset == 0
        return card {
            HStack {
                LocalizedText("Position").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $settings.customNotificationCenterDisplayID) {
                    LocalizedText("Where you click the clock").tag(CGDirectDisplayID(0))
                    if screens.count > 1 {
                        ForEach(screens, id: \.displayID) { screen in
                            Text(screen.nannyDisplayName).tag(screen.displayID)
                        }
                    }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
            }
            NCPanelPositionTile(screen: previewScreen,
                                anyScreen: settings.customNotificationCenterDisplayID == 0,
                                side: $settings.customNotificationCenterSide,
                                topOffset: $settings.customNotificationCenterTopOffset)
                .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                LocalizedText(settings.customNotificationCenterSide.labelKey)
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if settings.customNotificationCenterTopOffset > 0 {
                    Text("+\(Int(settings.customNotificationCenterTopOffset.rounded())) px")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(loc.string("Reset")) {
                    settings.customNotificationCenterSide = .right
                    settings.customNotificationCenterTopOffset = 0
                }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent).disabled(isDefault)
            }
            note(isDefault && settings.customNotificationCenterDisplayID == 0
                 ? "As macOS. Drag it on the preview to either side, and down from the top."
                 : "Drag it on the preview to either side, and down from the top.")
        }
    }

    // MARK: - Size

    private var sizeCard: some View {
        card {
            HStack {
                LocalizedText("Size").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button(loc.string("Reset")) { settings.customNotificationCenterScale = 1 }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                    .disabled(abs(settings.customNotificationCenterScale - 1) < 0.01)
            }
            HStack(spacing: 8) {
                Text("A").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $settings.customNotificationCenterScale, in: 0.8...1.4)
                    .onChange(of: settings.customNotificationCenterScale) { _, v in
                        if abs(v - 1) < 0.02 { settings.customNotificationCenterScale = 1 }
                    }
                    .controlSize(.mini)
                Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
                Text("\(Int((settings.customNotificationCenterScale * 100).rounded()))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
        }
    }

    // MARK: - Colours, as in the Banner tab, with "Same as banners" first

    private var backgroundCard: some View {
        let own = settings.customNotificationCenterOwnBackground
        let tint = settings.customNotificationCenterTint
        return card {
            HStack {
                LocalizedText("Background Color").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button(loc.string("Clear")) {
                    settings.customNotificationCenterOwnBackground = true
                    settings.customNotificationCenterTint = nil
                }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                .disabled(own && tint == nil)
            }
            HStack(spacing: 6) {
                sameAsBannersChip(selected: !own) { settings.customNotificationCenterOwnBackground = false }
                ForEach(BannerTabView.colorPresets, id: \.0) { name, color in
                    Button {
                        settings.customNotificationCenterOwnBackground = true
                        settings.customNotificationCenterTint = Self.tint(of: color)
                    } label: {
                        Circle().fill(color).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(
                                own && tint.map { BannerTabView.isColorMatch(color, $0.color) } == true
                                    ? Color.nannyStrong : Color.clear,
                                lineWidth: 2))
                    }
                    .buttonStyle(.plain).help(name)
                }
                Spacer()
                HStack(spacing: 4) {
                    LocalizedText("Custom").font(.system(size: 9)).foregroundStyle(.tertiary)
                    ColorPicker("", selection: Binding(
                        get: { tint?.color ?? settings.bannerColor },
                        set: {
                            settings.customNotificationCenterOwnBackground = true
                            settings.customNotificationCenterTint = Self.tint(of: $0)
                        }
                    ), supportsOpacity: false).labelsHidden()
                }
                .help(loc.string("Pick any custom color"))
            }
            note(!own ? "Same as your banners, and per app where your exceptions set one."
                 : tint == nil ? "No tint: the system's look." : "One tint for every row.")
        }
    }

    private var textCard: some View {
        let own = settings.customNotificationCenterOwnText
        let tint = settings.customNotificationCenterTextTint
        return card {
            HStack {
                LocalizedText("Text Color").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button(loc.string("Reset")) {
                    settings.customNotificationCenterOwnText = true
                    settings.customNotificationCenterTextTint = nil
                }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                .disabled(own && tint == nil)
            }
            HStack(spacing: 8) {
                sameAsBannersChip(selected: !own) { settings.customNotificationCenterOwnText = false }
                ColorPicker("Text", selection: Binding(
                    get: { tint?.color ?? settings.bannerTextTint?.color ?? .black },
                    set: {
                        settings.customNotificationCenterOwnText = true
                        settings.customNotificationCenterTextTint = Self.tint(of: $0)
                    }
                ), supportsOpacity: false)
                Spacer()
            }
            note(!own ? "Same as your banners."
                 : tint == nil ? "Default. Follows system appearance" : "Custom text color active.")
        }
    }

    private func sameAsBannersChip(selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LocalizedText("Same as banners")
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(selected ? Color.nannyProminent.opacity(0.9) : Color.nannyRaised(0.06),
                            in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private static func tint(of color: Color) -> BannerTint {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return BannerTint(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    // MARK: - Animation

    private var animationCard: some View {
        card {
            HStack {
                LocalizedText("Animation").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { previewReplay &+= 1 } label: {
                    Label { LocalizedText("Replay") } icon: { Image(systemName: "arrow.clockwise") }
                        .font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(Color.nannyAccent)
            }
            AnimationPreviewPane(animation: settings.customNotificationCenterAnimation, replay: previewReplay,
                                 tint: previewTint, textColor: previewTextColor)
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .background(Color.nannyInset(0.22), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture { previewReplay &+= 1 }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
                ForEach(BannerAnimation.allCases, id: \.self) { animationChip($0) }
            }
            note(settings.customNotificationCenterAnimation == .default
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

    private func animationChip(_ anim: BannerAnimation) -> some View {
        let selected = settings.customNotificationCenterAnimation == anim
        return Button {
            settings.customNotificationCenterAnimation = anim
            previewReplay &+= 1
        } label: {
            HStack(spacing: 5) {
                Image(systemName: anim.iconName).font(.system(size: 10))
                Text(anim.label).font(.caption)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.nannyProminent.opacity(0.9) : Color.nannyRaised(0.06),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Extras

    private var extrasCard: some View {
        card {
            LocalizedText("Extras").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            toggleRow("Show when notifications arrived", isOn: $settings.customNotificationCenterTimes)
            toggleRow("Filter by app", isOn: $settings.customNotificationCenterAppFilter)
            note("Not part of macOS's Notification Center, so off unless you turn them on. Times are noted when each banner appears; notifications that came in while NotificationNanny wasn't running have none.")
        }
    }

    // MARK: - Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.nannyRaised(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func note(_ key: String) -> some View {
        LocalizedText(key).font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleRow(_ key: String, isOn: Binding<Bool>) -> some View {
        HStack {
            LocalizedText(key).font(.callout)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

/// The display as a device, as on the Position tab, with Notification Center's column on
/// it at its real size. Drag it: it snaps to either side, and goes down from the top.
private struct NCPanelPositionTile: View {
    let screen: NSScreen
    /// No display is chosen: it opens wherever the clock is clicked, so the preview is a
    /// plain screen rather than one particular laptop or monitor.
    var anyScreen = false
    @Binding var side: NCPanelSide
    @Binding var topOffset: Double
    var maxWidth: CGFloat = 438
    var maxHeight: CGFloat = 260

    private static let rowSize = CGSize(width: 344, height: 58)
    private static let rowGap: CGFloat = 6
    private static let rows = 3
    private static var columnHeight: CGFloat { rowSize.height * CGFloat(rows) + rowGap * CGFloat(rows - 1) }

    var body: some View {
        let frame = screen.frame
        let menuBar = max(0, frame.maxY - screen.visibleFrame.maxY)
        let scale = min(maxWidth / max(frame.width, 1), maxHeight / max(frame.height, 1))
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        let edge = CustomNCPanelController.rightInset
        let x: CGFloat
        switch side {
        case .right: x = frame.width - edge - Self.rowSize.width
        case .center: x = (frame.width - Self.rowSize.width) / 2
        case .left: x = edge
        }
        let y = CustomNCPanelController.topInset + topOffset

        let picture = ZStack(alignment: .topLeading) {
            Rectangle().fill(LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.20),
                                                     Color(red: 0.08, green: 0.09, blue: 0.12)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(Color.white.opacity(0.16)).frame(height: menuBar * scale)
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
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { value in
            move(to: value.location, scale: scale, screenHeight: frame.height)
        })

        return Group {
            if anyScreen {
                picture
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            } else {
                DeviceChrome(screen: screen, screenSize: size) { picture }
            }
        }
    }

    /// The column's middle follows the pointer: the third of the screen picks left, middle
    /// or right, the height how far down it starts, never above the system's place or off
    /// screen.
    private func move(to point: CGPoint, scale: CGFloat, screenHeight: CGFloat) {
        let third = screen.frame.width * scale / 3
        let newSide: NCPanelSide = point.x < third ? .left : point.x < third * 2 ? .center : .right
        let top = point.y / scale - Self.columnHeight / 2 - CustomNCPanelController.topInset
        let limit = max(0, screenHeight - CustomNCPanelController.topInset - Self.columnHeight - 16)
        var offset = min(max(0, top), limit)
        if offset < 8 { offset = 0 }
        offset = offset.rounded()
        if newSide != side { side = newSide }
        if abs(offset - topOffset) >= 1 { topOffset = offset }
    }
}
