import SwiftUI
import AppKit

extension Color {
    static let nannyAccent = Color(red: 0x89 / 255, green: 0x5C / 255, blue: 0x9B / 255)
}

package struct MenuBarContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin
    @Environment(\.openWindow) private var openWindow

    @State private var newerVersion: String? = nil

    package init() {}

    private var screens: [NSScreen] { NSScreen.screens }

    private var selectedScreen: NSScreen {
        if settings.targetDisplayID != 0,
           let s = screens.first(where: { $0.displayID == settings.targetDisplayID }) { return s }
        return NSScreen.main ?? screens[0]
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if screens.count > 1 {
                Divider()
                screenPickerSection
            }
            Divider()
            positionSection
            Divider()
            actionSection
        }
        .padding(16)
        .frame(width: 320)
        .tint(Color.nannyAccent)
        .onAppear {
            repositioner.refreshAccessibilityStatus()
            if repositioner.hasAccessibilityPermission, !repositioner.isObserving {
                repositioner.startObserving()
            }
            // Auto-update check disabled for now.
            // Task { newerVersion = await UpdateChecker.fetchNewerVersion() }
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
                if !repositioner.hasAccessibilityPermission {
                    Button { repositioner.requestAccessibilityPermission() } label: {
                        statusLine
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    statusLine
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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

    private var screenPickerSection: some View {
        HStack(spacing: 8) {
            Text("Show on")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $settings.targetDisplayID) {
                Text("Auto").tag(CGDirectDisplayID(0))
                ForEach(screens, id: \.displayID) { screen in
                    Text(screen.nannyDisplayName).tag(screen.displayID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            Spacer()
        }
    }

    // MARK: - Default position tile

    private var positionSection: some View {
        let visible = selectedScreen.visibleFrame
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Default Position")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(visible.width)) × \(Int(visible.height))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            DraggableScreenTile(
                screen: selectedScreen,
                placement: settings.placementBinding(for: selectedScreen)
            )
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 6) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Label("Extended Settings", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button {
                repositioner.sendTestNotification(groupID: nil)
            } label: {
                Label("Send Test Notification", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.secondary)

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
                if let newerVersion {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/chessper53/NotificationNanny/releases/latest")!)
                    } label: {
                        Label("v\(newerVersion) available", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.green)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }
}
