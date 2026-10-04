import SwiftUI
import AppKit

extension NSColor {
    static let nannyAmber      = NSColor(srgbRed: 0xE8 / 255, green: 0x83 / 255, blue: 0x3A / 255, alpha: 1)
    static let nannyAmberDeep  = NSColor(srgbRed: 0xA8 / 255, green: 0x55 / 255, blue: 0x14 / 255, alpha: 1)
    static let nannyGraphite   = NSColor(srgbRed: 0x2A / 255, green: 0x2D / 255, blue: 0x34 / 255, alpha: 1)
}

extension Color {
    /// Amber, adapting per appearance: the bright amber reads well on the dark
    /// settings window but drops under 3:1 as caption text on a light one, so
    /// light mode gets a deeper burnt amber. For text, icons and small marks;
    /// large fills use `nannyProminent`.
    static let nannyAccent = Color(nsColor: NSColor(name: "nannyAccent") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .nannyAmber : .nannyAmberDeep
    })

    /// Large accent fills: the prominent button, switches, segmented controls, a
    /// selected chip. Amber on dark, as before. On a light window a large area of
    /// the deep amber reads as brown, so light mode fills with graphite and keeps
    /// amber for the small accents.
    static let nannyProminent = nannyAdaptive(light: .nannyGraphite, dark: .nannyAmber)

    /// A wash behind a selected or highlighted item. Amber on dark, as before. On
    /// light, amber at these opacities over white turns tan, so it is a neutral
    /// grey there; the amber stays on the icon or text on top.
    static func nannyWash(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.32),
                      dark: NSColor.nannyAmber.withAlphaComponent(opacity))
    }

    /// The icon of the selected sidebar item: white on dark as before, amber on
    /// light, where it carries the accent the neutral wash behind it no longer does.
    static let nannySelectedIcon = nannyAdaptive(light: .nannyAmberDeep, dark: .white)

    /// Picks a colour by the appearance the view is drawn in. The settings tokens below
    /// keep their original dark values exactly, so only light mode gains new colours.
    static func nannyAdaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static let nannyWindow = nannyAdaptive(light: NSColor(white: 0.95, alpha: 1),
                                           dark: NSColor(white: 0.10, alpha: 1))
    static let nannySidebar = nannyAdaptive(light: .black.withAlphaComponent(0.04),
                                            dark: .black.withAlphaComponent(0.5))
    /// Text on a selected sidebar item or swatch ring: white on dark, label colour on light.
    static let nannyStrong = nannyAdaptive(light: .labelColor, dark: .white)

    /// Cards and hairlines: a white lift on dark, a lighter black shade on light, since
    /// the same opacity of black reads much heavier against a light window.
    static func nannyRaised(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.7),
                      dark: .white.withAlphaComponent(opacity))
    }

    /// Recessed wells such as log views: black on both, much fainter on light.
    static func nannyInset(_ opacity: CGFloat) -> Color {
        nannyAdaptive(light: .black.withAlphaComponent(opacity * 0.35),
                      dark: .black.withAlphaComponent(opacity))
    }

    /// Muted grey text. The fixed dark greys drop under 3:1 on a light window, so light
    /// mode uses the system secondary label colour instead.
    static func nannyMuted(_ darkWhite: CGFloat) -> Color {
        nannyAdaptive(light: .secondaryLabelColor, dark: NSColor(white: darkWhite, alpha: 1))
    }
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
        settings.resolvedTargetScreen() ?? NSScreen.main ?? screens[0]
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if settings.isEnabled {
                Divider()
                snoozeSection
            }
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
        .tint(Color.nannyProminent)
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
            Image.nannyGlyph(.bell, pointSize: 20)
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

    // MARK: - Snooze

    @ViewBuilder
    private var snoozeSection: some View {
        if settings.isSnoozed, let until = settings.snoozedUntil {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Paused").font(.caption.weight(.medium))
                    Text("Resumes at \(Self.timeFormatter.string(from: until))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Resume") { settings.endSnooze() }
                    .controlSize(.small)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz").foregroundStyle(.secondary)
                Text("Pause repositioning").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Pause for…") {
                    Button("15 minutes") { settings.snooze(minutes: 15) }
                    Button("30 minutes") { settings.snooze(minutes: 30) }
                    Button("1 hour")     { settings.snooze(minutes: 60) }
                    Button("4 hours")    { settings.snooze(minutes: 240) }
                }
                .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

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
