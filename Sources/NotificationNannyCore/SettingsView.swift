import SwiftUI
import AppKit
import UserNotifications

package struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin

    enum NavTab: Hashable { case position, exceptions, presets, general, banner, backup, help }

    @State private var activeTab: NavTab = .position
    @State private var newerVersion: String? = nil
    @State private var isBannerDismissed = false
    @State private var permissionJustGranted = false
    @StateObject private var brewUpdater = HomebrewUpdater()

    package init() {}

    package var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if !repositioner.hasAccessibilityPermission || permissionJustGranted {
                    accessibilityBanner(granted: permissionJustGranted)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let newer = newerVersion, !isBannerDismissed {
                    updateBanner(version: newer)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: repositioner.hasAccessibilityPermission)
            .animation(.easeInOut(duration: 0.35), value: newerVersion)
            .animation(.easeInOut(duration: 0.35), value: isBannerDismissed)
            .onChange(of: repositioner.hasAccessibilityPermission) { _, granted in
                guard granted else { return }
                permissionJustGranted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.35)) { permissionJustGranted = false }
                }
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarItem("Position",   systemImage: "scope",                   tab: .position)
                    sidebarItem("Exceptions", systemImage: "app.badge",               tab: .exceptions)
                    sidebarItem("Banner",     systemImage: "textformat.size",         tab: .banner)
                    sidebarItem("Presets",    systemImage: "star",                    tab: .presets)
                    sidebarItem("General",    systemImage: "gearshape",               tab: .general)
                    sidebarItem("Backup",     systemImage: "tray.and.arrow.up",       tab: .backup)
                    Spacer()
                    sidebarItem("Help",       systemImage: "questionmark.circle",     tab: .help)
                    Divider().padding(.horizontal, 8).padding(.vertical, 4)
                    Button {
                        settings.isEnabled.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: settings.isEnabled ? "pause.circle" : "play.circle")
                                .frame(width: 16, alignment: .center)
                            Text(settings.isEnabled ? "Disable" : "Enable")
                            Spacer()
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .foregroundStyle(settings.isEnabled ? Color.orange.opacity(0.8) : Color.green.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "power").frame(width: 16, alignment: .center)
                            Text("Quit")
                            Spacer()
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .foregroundStyle(Color(white: 0.45))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("q")
                    Group {
                        if let newer = newerVersion, isBannerDismissed {
                            Button {
                                withAnimation(.easeInOut(duration: 0.35)) { isBannerDismissed = false }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("v\(appVersion)")
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.nannyAccent)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("v\(newer) available — click to update")
                        } else {
                            Text("v\(appVersion)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                .padding(8)
                .frame(width: 150)
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.5))

                Divider()

                ScrollView {
                    Group {
                        switch activeTab {
                        case .position:   PositionTabView()
                        case .banner:     BannerTabView()
                        case .exceptions: ExceptionsTabView()
                        case .presets:    PresetsTabView()
                        case .general:    GeneralTabView()
                        case .backup:     BackupTabView()
                        case .help:       HelpTabView()
                        }
                    }
                    .padding(16)
                }
                .id(activeTab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.10))
        .background(WindowSizeLock(width: 660, height: 640))
        .tint(Color.nannyAccent)
        .preferredColorScheme(.dark)
        .onAppear {
            repositioner.refreshAccessibilityStatus()
            if repositioner.hasAccessibilityPermission, !repositioner.isObserving {
                repositioner.startObserving()
            }
            Task { newerVersion = await UpdateChecker.fetchNewerVersion() }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func sidebarItem(_ label: String, systemImage: String, tab: NavTab) -> some View {
        Button { activeTab = tab } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 16, alignment: .center)
                Text(label)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                activeTab == tab ? Color.nannyAccent.opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(activeTab == tab ? Color.white : Color(white: 0.55))
        }
        .buttonStyle(.plain)
    }

    private func accessibilityBanner(granted: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.callout)
                .foregroundStyle(granted ? .green : .orange)
                .animation(.easeInOut(duration: 0.2), value: granted)
            VStack(alignment: .leading, spacing: 1) {
                Text(granted ? "Accessibility access granted" : "Accessibility access required")
                    .font(.callout.weight(.semibold))
                    .animation(.easeInOut(duration: 0.2), value: granted)
                if !granted {
                    Text("NotificationNanny needs this to reposition and intercept notification banners.")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if !granted {
                Button("Grant Access") { repositioner.requestAccessibilityPermission() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background((granted ? Color.green : Color.orange).opacity(0.18))
        .animation(.easeInOut(duration: 0.3), value: granted)
    }

    private func updateBanner(version: String) -> some View {
        HStack(spacing: 10) {
            // Leading icon
            Group {
                switch brewUpdater.state {
                case .idle:
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                case .running:
                    ProgressView().controlSize(.small)
                case .succeeded:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
            }
            .frame(width: 18, alignment: .center)

            // Description
            VStack(alignment: .leading, spacing: 1) {
                switch brewUpdater.state {
                case .idle:
                    Text("v\(version) is available")
                        .font(.callout.weight(.semibold))
                case .running:
                    Text("Updating via Homebrew\u{2026}")
                        .font(.callout.weight(.semibold))
                    if let last = brewUpdater.outputLines.last {
                        Text(last)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5))
                            .lineLimit(1)
                    }
                case .succeeded:
                    Text("Updated to v\(version)")
                        .font(.callout.weight(.semibold))
                    Text("Relaunch to apply changes")
                        .font(.caption2).foregroundStyle(.secondary)
                case .failed(let msg):
                    Text("Update failed")
                        .font(.callout.weight(.semibold))
                    Text(msg)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action button
            switch brewUpdater.state {
            case .idle:
                if InstallSource.current == .homebrew {
                    Button("Update Now") { brewUpdater.start() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Button("View Release") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/chessper53/NotificationNanny/releases/latest")!)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
            case .running:
                EmptyView()
            case .succeeded:
                Button("Relaunch") { brewUpdater.relaunch() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            case .failed:
                Button("View Release") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/chessper53/NotificationNanny/releases/latest")!)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }

            // Dismiss — hidden while update is in progress
            if brewUpdater.state != .running {
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { isBannerDismissed = true }
                } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain).foregroundStyle(Color(white: 0.5))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(updateBannerAccent.opacity(0.12))
    }

    private var updateBannerAccent: Color {
        if case .failed = brewUpdater.state { return .orange }
        return .green
    }
}

// Bypasses SwiftUI's content-driven window sizing by reaching into the NSWindow directly.
private struct WindowSizeLock: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let size = NSSize(width: width, height: height)
            window.minSize = size
            window.maxSize = size
            window.setContentSize(size)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Shared helper: labelled slider + numeric field pair. Used by Position and Exceptions tabs.
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Slider(value: $value, in: range).controlSize(.mini)
                TextField("0", value: $value, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.mini)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .font(.caption2.monospacedDigit())
                Text("px").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
