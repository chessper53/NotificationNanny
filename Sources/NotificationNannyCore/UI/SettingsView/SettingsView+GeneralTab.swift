import AppKit
import SwiftUI

struct GeneralTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var launchAtLogin: LaunchAtLogin
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var focus = FocusModeMonitor.shared

    @State private var showResetConfirmation = false
    @State private var showHideIconConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LocalizedText("App-wide settings for startup, timing, and notification behaviour. These apply globally and are not affected by presets or per-app rules.")
                .font(.callout)
                .foregroundStyle(Color.nannyMuted(0.55))
                .fixedSize(horizontal: false, vertical: true)

            section("Language") {
                HStack {
                    LocalizedText("App Language").font(.callout)
                    Spacer()
                    NannyMenuPicker(selection: Binding(
                        get: { loc.language },
                        set: { loc.setLanguage($0) }
                    ), options: AppLanguage.allCases.map { .init(value: $0, title: $0.title) },
                       systemImage: "globe")
                }
                .settingsListRow()
            }

            section("Appearance") {
                HStack {
                    LocalizedText("Settings window").font(.callout)
                    Spacer()
                    NannySegmentedPicker(selection: $settings.settingsAppearance,
                                         options: SettingsAppearance.allCases.map { .init(value: $0, titleKey: $0.labelKey) },
                                         compact: true)
                }
                .settingsListRow()
            }

            section("Startup") {
                toggleRow("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                Divider().padding(.leading, 14)
                // Confirm hiding the only visible Settings entry; showing the icon needs no
                // confirmation.
                toggleRow("Hide menu bar icon", isOn: Binding(
                    get: { settings.hideMenuBarIcon },
                    set: { shouldHide in
                        if shouldHide {
                            showHideIconConfirmation = true
                        } else {
                            settings.hideMenuBarIcon = false
                        }
                    }
                ))
            }
            .confirmationDialog(loc.string("Hide the menu bar icon?"),
                                isPresented: $showHideIconConfirmation,
                                titleVisibility: .visible) {
                Button(loc.string("Hide")) { settings.hideMenuBarIcon = true }
                Button(loc.string("Cancel"), role: .cancel) {}
            } message: {
                LocalizedText("NotificationNanny keeps running and keeps moving your banners. To open Settings again, launch NotificationNanny from your Applications folder.")
            }

            section("Timing") {
                autoDismissRow
            }

            section("Pausing") {
                toggleRow("Pause while screen sharing", isOn: $settings.pauseWhileStreaming)
                Divider().padding(.leading, 14)
                toggleRow("Pause during Focus / Do Not Disturb", isOn: $settings.pauseDuringFocus)
                if settings.pauseDuringFocus, focus.storeReadable == false {
                    focusAccessRow.padding(.horizontal, 14).padding(.bottom, 10)
                }
                Divider().padding(.leading, 14)
                toggleRow("Blur banner text (privacy)", isOn: $settings.redactBannerContent)
            }

            section("Placement & safety") {
                toggleRow("Send to the screen with the cursor", isOn: $settings.followActiveScreen)
                Divider().padding(.leading, 14)
                toggleRow("Don't move Notification Center", isOn: $settings.avoidNCPanel,
                          detail: "When on, Notification Center opens on the screen whose clock you click. When off, it always moves to the screen your banners go to, and on a smaller screen than the one it opened on, its bottom is cut off.")
                Divider().padding(.leading, 14)
                toggleRow("Don't move desktop widgets", isOn: $settings.protectDesktopWidgets)
                Divider().padding(.leading, 14)
                toggleRow("Hold banners while display is asleep", isOn: $settings.holdWhileAsleep)
            }

            if let error = launchAtLogin.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 6) {
                LocalizedText("Import & Export")
                    .textCase(.uppercase)
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).kerning(0.5)
                    .padding(.leading, 4)
                BackupTabView()
            }

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label {
                    LocalizedText("Reset All Settings")
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .confirmationDialog(loc.string("Reset all settings?"),
                                isPresented: $showResetConfirmation,
                                titleVisibility: .visible) {
                Button(loc.string("Reset"), role: .destructive) { settings.resetAllSettings() }
                Button(loc.string("Cancel"), role: .cancel) {}
            } message: {
                LocalizedText("This will clear all positions, exceptions, presets and restore defaults. This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ titleKey: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(titleKey)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).kerning(0.5)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .settingsCardBackground()
        }
    }

    /// Explain unreadable Focus state and offer Full Disk Access settings.
    private var focusAccessRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
            SettingsNote("Pause during Focus needs Full Disk Access. Without it, NotificationNanny can't tell when a Focus is on, so it never pauses. After allowing it, quit and reopen NotificationNanny.")
            Spacer()
            Button(loc.string("Open System Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
    }

    private func toggleRow(_ labelKey: String, isOn: Binding<Bool>, detail: String? = nil) -> some View {
        SettingsToggleRow(labelKey, isOn: isOn, detail: detail).settingsListRow()
    }

    private var autoDismissRow: some View {
        HStack(spacing: 8) {
            LocalizedText("Auto-dismiss").font(.callout)
            Spacer()
            if settings.autoDismissSeconds > 0 {
                TextField("", value: $settings.autoDismissSeconds,
                          format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder).controlSize(.mini)
                    .multilineTextAlignment(.trailing).frame(width: 40)
                    .font(.caption2.monospacedDigit())
                Stepper("", value: $settings.autoDismissSeconds, in: 1...300, step: 1)
                    .labelsHidden().controlSize(.mini)
                LocalizedText("s").font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(
                get: { settings.autoDismissSeconds > 0 },
                set: { settings.autoDismissSeconds = $0 ? 10 : 0 }
            ))
            .labelsHidden().toggleStyle(.nannySwitch).controlSize(.small)
        }
        .settingsListRow()
    }
}
