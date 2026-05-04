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

    /// Always resolve from the live screens list — display IDs come and go.
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
            actionSection
        }
        .padding(16)
        .frame(width: 320)
        .tint(Color.nannyAccent)
        .onAppear {
            syncSelectedDisplay()
            // Re-check permission every time the popover opens so granting in
            // System Settings is reflected without needing to restart.
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

    // MARK: - Position grid (matches the screen's aspect ratio)

    private var positionSection: some View {
        let placement = settings.placementBinding(for: selectedScreen)
        let visible = selectedScreen.visibleFrame
        let aspect = visible.width / max(visible.height, 1)
        let gridWidth: CGFloat = 288    // popover (320) − horizontal padding (16+16)
        let gridHeight: CGFloat = min(200, max(80, gridWidth / aspect))
        let spacing: CGFloat = 6
        let cellWidth = (gridWidth - spacing * 2) / 3
        let cellHeight = (gridHeight - spacing * 2) / 3

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
            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { col in
                            let pos = positionFor(row: row, col: col)
                            PositionTile(
                                position: pos,
                                isSelected: placement.wrappedValue.position == pos,
                                size: CGSize(width: cellWidth, height: cellHeight)
                            ) {
                                placement.wrappedValue.position = pos
                            }
                        }
                    }
                }
            }
            .frame(width: gridWidth, height: gridHeight)
        }
    }

    private func positionFor(row: Int, col: Int) -> NotificationPosition {
        switch (row, col) {
        case (0, 0): return .topLeft
        case (0, 1): return .topCenter
        case (0, 2): return .topRight
        case (1, 0): return .middleLeft
        case (1, 1): return .middleCenter
        case (1, 2): return .middleRight
        case (2, 0): return .bottomLeft
        case (2, 1): return .bottomCenter
        default:     return .bottomRight
        }
    }

    // MARK: - Offset sliders (range = full screen dimensions)

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

// MARK: - Position tile

private struct PositionTile: View {
    let position: NotificationPosition
    let isSelected: Bool
    let size: CGSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: position.alignment) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                          ? Color.nannyAccent.opacity(0.18)
                          : Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? Color.nannyAccent : Color.secondary.opacity(0.25),
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
                Capsule()
                    .fill(isSelected ? Color.nannyAccent : Color.secondary)
                    .frame(width: min(20, size.width * 0.4),
                           height: max(4, min(6, size.height * 0.18)))
                    .padding(5)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(position.label)
    }
}

// MARK: - Test notification

enum TestNotification {
    /// Fires a banner via AppleScript so we don't have to ask for our own
    /// UNUserNotificationCenter authorization just to verify positioning.
    static func send() {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        let script = """
        display notification "Thank you for using NotificationNanny!" with title "NotificationNanny" subtitle "Test #\(stamp)"
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()

        // Diagnostic probe — log all on-screen windows shortly after the
        // banner should have appeared, to see which process owns it.
        NotificationProbe.dumpOnScreenWindows(tag: "before")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationProbe.dumpOnScreenWindows(tag: "t+0.4s")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NotificationProbe.dumpOnScreenWindows(tag: "t+1.5s")
        }
    }
}
