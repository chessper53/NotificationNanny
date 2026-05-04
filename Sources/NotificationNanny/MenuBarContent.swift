import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner

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
        .onAppear { syncSelectedDisplay() }
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

    // MARK: - Position grid

    private var positionSection: some View {
        let placement = settings.placementBinding(for: selectedScreen)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Position")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if screens.count > 1 {
                    Text(selectedScreen.nannyDisplayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                spacing: 6
            ) {
                ForEach(NotificationPosition.allCases) { pos in
                    PositionTile(
                        position: pos,
                        isSelected: placement.wrappedValue.position == pos
                    ) {
                        placement.wrappedValue.position = pos
                    }
                }
            }
        }
    }

    // MARK: - Offset sliders

    private var offsetSection: some View {
        let placement = settings.placementBinding(for: selectedScreen)
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
            sliderRow(
                title: "Horizontal",
                value: placement.xOffset,
                range: -400...400,
                hint: placement.wrappedValue.xOffset >= 0 ? "right" : "left"
            )
            sliderRow(
                title: "Vertical",
                value: placement.yOffset,
                range: -400...400,
                hint: placement.wrappedValue.yOffset >= 0 ? "down" : "up"
            )
        }
    }

    private func sliderRow(title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption2)
                Spacer()
                Text("\(Int(value.wrappedValue)) px \(hint)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.mini)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: position.alignment) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.18)
                          : Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 5)
                    .padding(5)
            }
            .frame(height: 38)
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
        display notification "Drag the sliders to reposition me!" with title "NotificationNanny" subtitle "Test #\(stamp)"
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }
}
