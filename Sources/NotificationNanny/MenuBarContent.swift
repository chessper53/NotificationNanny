import SwiftUI
import AppKit

extension Color {
    /// Brand accent — purple (#895C9B).
    static let nannyAccent = Color(red: 0x89 / 255, green: 0x5C / 255, blue: 0x9B / 255)
}

struct MenuBarContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    @State private var selectedDisplayID: CGDirectDisplayID =
        NSScreen.main?.displayID ?? NSScreen.screens.first?.displayID ?? 0

    private var screens: [NSScreen] { NSScreen.screens }

    private var selectedScreen: NSScreen {
        screens.first(where: { $0.displayID == selectedDisplayID })
            ?? NSScreen.main
            ?? screens.first!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if screens.count > 1 {
                screenPicker
                Divider()
            }
            positionSection
            Divider()
            offsetSection
            Divider()
            autoDismissSection
            Divider()
            perAppSection
            Divider()
            actionSection
        }
        .padding(16)
        .frame(width: 320)
        .tint(Color.nannyAccent)
        .onAppear {
            syncSelectedDisplay()
            repositioner.refreshAccessibilityStatus()
            if repositioner.hasAccessibilityPermission, !repositioner.isObserving {
                repositioner.startObserving()
            }
        }
    }

    private func syncSelectedDisplay() {
        if !screens.contains(where: { $0.displayID == selectedDisplayID }) {
            selectedDisplayID = NSScreen.main?.displayID ?? screens.first?.displayID ?? 0
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("NotificationNanny")
                    .font(.headline)
                statusLine
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $settings.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !repositioner.hasAccessibilityPermission {
            Label("Needs Accessibility access", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if repositioner.isObserving {
            Label("Watching notifications", systemImage: "eye.fill")
        } else {
            Label("Idle", systemImage: "pause.circle")
        }
    }

    // MARK: - Screen picker

    private var screenPicker: some View {
        HStack(spacing: 8) {
            Text("Configuring")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $selectedDisplayID) {
                ForEach(screens, id: \.displayID) { screen in
                    Text(screen.nannyDisplayName)
                        .tag(screen.displayID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            Spacer()
        }
    }

    // MARK: - Position tile

    private var positionSection: some View {
        let visible = selectedScreen.visibleFrame
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Position")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(visible.width)) × \(Int(visible.height))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if screens.count > 1 {
                    Text("· \(selectedScreen.nannyDisplayName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            DraggableScreenTile(
                screen: selectedScreen,
                placement: settings.placementBinding(for: selectedScreen)
            )
        }
    }

    // MARK: - Offset sliders

    private var offsetSection: some View {
        let placement = settings.placementBinding(for: selectedScreen)
        let visible = selectedScreen.visibleFrame
        let width = Double(visible.width)
        let height = Double(visible.height)
        let xRange = -width ... width
        let yRange = -height ... height
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fine-tune")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    placement.wrappedValue.xOffset = 0
                    placement.wrappedValue.yOffset = 0
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .disabled(placement.wrappedValue.xOffset == 0
                          && placement.wrappedValue.yOffset == 0)
            }
            sliderRow(title: "Horizontal", value: placement.xOffset, range: xRange)
            sliderRow(title: "Vertical",   value: placement.yOffset, range: yRange)
        }
    }

    private func sliderRow(title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Slider(value: value, in: range)
                    .controlSize(.mini)
                TextField(
                    "0",
                    value: value,
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .font(.caption2.monospacedDigit())
                Text("px")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Auto-dismiss

    private var autoDismissSection: some View {
        HStack(spacing: 8) {
            Text("Auto-dismiss")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if settings.autoDismissSeconds > 0 {
                TextField(
                    "",
                    value: $settings.autoDismissSeconds,
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                .font(.caption2.monospacedDigit())
                Stepper("", value: $settings.autoDismissSeconds, in: 1...300, step: 1)
                    .labelsHidden()
                    .controlSize(.mini)
                Text("s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(
                get: { settings.autoDismissSeconds > 0 },
                set: { settings.autoDismissSeconds = $0 ? 10 : 0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Per-app positions

    /// Running apps that can be added manually (not already in the list).
    private var addableApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .filter { !settings.knownApps.contains($0) && $0 != "NotificationNanny" }
            .sorted()
    }

    private var perAppSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Per-app positions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    if addableApps.isEmpty {
                        Text("No other apps running")
                    } else {
                        ForEach(addableApps, id: \.self) { appName in
                            Button(appName) { settings.recordApp(appName) }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if settings.knownApps.isEmpty {
                Text("Apps appear here automatically after their first notification, or add one via +.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) {
                    ForEach(settings.knownApps, id: \.self) { app in
                        AppOverrideRow(appName: app, settings: settings)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button {
                TestNotification.send()
            } label: {
                Label("Send Test Notification", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if !repositioner.hasAccessibilityPermission {
                Button {
                    repositioner.requestAccessibilityPermission()
                } label: {
                    Label("Grant Accessibility Permission…", systemImage: "lock.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.caption)

            if let error = launchAtLogin.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
}

// MARK: - Per-app override row

private struct AppOverrideRow: View {
    let appName: String
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @State private var expanded = false

    private var placementBinding: Binding<ScreenPlacement> {
        settings.appPlacementBinding(for: appName)
    }

    var body: some View {
        let hasOverride = settings.appPlacement(for: appName) != nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(appName)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if hasOverride {
                    Text(placementBinding.wrappedValue.position.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Global")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    settings.forgetApp(appName)
                    expanded = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            if expanded {
                HStack(alignment: .top, spacing: 10) {
                    PositionGrid(
                        selection: Binding(
                            get: { placementBinding.wrappedValue.position },
                            set: { var p = placementBinding.wrappedValue; p.position = $0; placementBinding.wrappedValue = p }
                        )
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        appOffsetField("X", value: Binding(
                            get: { placementBinding.wrappedValue.xOffset },
                            set: { var p = placementBinding.wrappedValue; p.xOffset = $0; placementBinding.wrappedValue = p }
                        ))
                        appOffsetField("Y", value: Binding(
                            get: { placementBinding.wrappedValue.yOffset },
                            set: { var p = placementBinding.wrappedValue; p.yOffset = $0; placementBinding.wrappedValue = p }
                        ))
                        Spacer(minLength: 0)
                        HStack {
                            Button {
                                repositioner.sendTest(as: appName)
                            } label: {
                                Image(systemName: "paperplane.fill")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .help("Send a test notification as \(appName)")
                            Spacer()
                            Button("Reset") {
                                var p = placementBinding.wrappedValue
                                p.xOffset = 0; p.yOffset = 0
                                placementBinding.wrappedValue = p
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .disabled(placementBinding.wrappedValue.xOffset == 0
                                      && placementBinding.wrappedValue.yOffset == 0)
                        }
                    }
                }
                .padding(.bottom, 2)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private func appOffsetField(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .leading)
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .font(.caption2.monospacedDigit())
            Text("px")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 3×3 position grid

private struct PositionGrid: View {
    @Binding var selection: NotificationPosition

    private static let rows: [[NotificationPosition]] = [
        [.topLeft,    .topCenter,    .topRight],
        [.middleLeft, .middleCenter, .middleRight],
        [.bottomLeft, .bottomCenter, .bottomRight],
    ]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row) { pos in
                        Button {
                            selection = pos
                        } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(selection == pos
                                      ? Color.nannyAccent
                                      : Color.secondary.opacity(0.15))
                                .frame(width: 28, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .help(pos.label)
                    }
                }
            }
        }
    }
}

// MARK: - Drag-to-position tile

private struct DraggableScreenTile: View {
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
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            BannerChip(width: bannerWidth, height: bannerHeight)
                .position(x: bannerCenterTile.x, y: bannerCenterTile.y)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            updatePlacement(
                                fromTilePoint: value.location,
                                tileSize: CGSize(width: tileWidth, height: tileHeight),
                                visible: visible
                            )
                        }
                )
        }
        .frame(width: tileWidth, height: tileHeight)
        .contentShape(Rectangle())
        .onTapGesture { tap in
            updatePlacement(
                fromTilePoint: tap,
                tileSize: CGSize(width: tileWidth, height: tileHeight),
                visible: visible
            )
        }
    }

    private func bannerCenterInVisibleCoords(visible: CGRect) -> CGPoint {
        let banner = Self.realBannerSize
        let inset: CGFloat = 8
        let x: CGFloat
        switch placement.position {
        case .topLeft, .middleLeft, .bottomLeft:
            x = inset
        case .topCenter, .middleCenter, .bottomCenter:
            x = (visible.width - banner.width) / 2
        case .topRight, .middleRight, .bottomRight:
            x = visible.width - banner.width - inset
        }
        let y: CGFloat
        switch placement.position {
        case .topLeft, .topCenter, .topRight:
            y = inset
        case .middleLeft, .middleCenter, .middleRight:
            y = (visible.height - banner.height) / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = visible.height - banner.height - inset
        }
        let cx = visible.minX + x + banner.width / 2 + CGFloat(placement.xOffset)
        let cy = visible.minY + y + banner.height / 2 + CGFloat(placement.yOffset)
        return CGPoint(x: cx, y: cy)
    }

    private func updatePlacement(fromTilePoint point: CGPoint,
                                 tileSize: CGSize,
                                 visible: CGRect) {
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

        let anchor = position(for: bandX, bandY)

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
        placement.xOffset = Double(centreX - refX)
        placement.yOffset = Double(centreY - refY)
    }

    private enum AnchorBand { case start, middle, end }

    private func position(for x: AnchorBand, _ y: AnchorBand) -> NotificationPosition {
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

private struct BannerChip: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.nannyAccent.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.nannyAccent, lineWidth: 1)
            )
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

// MARK: - Test notification

enum TestNotification {
    static func send() {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        let script = """
        display notification "Thank you for using NotificationNanny!" with title "NotificationNanny" subtitle "Test #\(stamp)"
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }
}
