import AppKit
import SwiftUI

struct NotificationCenterTabView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var permission = ScreenRecordingPermission.shared
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LocalizedText("NotificationNanny can show its own list when you click the clock, in place of the Notification Center panel. Your notifications stay in Notification Center: this is another view of them, and everything you do in it goes back there.")
                .font(.callout)
                .foregroundStyle(Color.nannyMuted(0.55))
                .fixedSize(horizontal: false, vertical: true)

            section("Notification Center") {
                toggleRow("Use NotificationNanny's Notification Center (experimental)",
                          isOn: $settings.customNotificationCenter)
            }

            if settings.customNotificationCenter {
                section("List") {
                    toggleRow("Show when notifications arrived", isOn: $settings.customNotificationCenterTimes,
                              detail: "Notification Center doesn't share its times, so NotificationNanny notes when each banner appears. Notifications that came in while it wasn't running have no time.")
                    Divider().padding(.leading, 14)
                    toggleRow("Filter by app", isOn: $settings.customNotificationCenterAppFilter,
                              detail: "A row of apps above the list; click one to see only its notifications.")
                }

                section("Look") {
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedText("Rows look like your banners: their colour, text colour and privacy blur come from the Banner tab and your exceptions.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        LocalizedText("Animation").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
                            ForEach(BannerAnimation.allCases, id: \.self) { animationChip($0) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }

                section("Widgets") {
                    LocalizedText("Widgets are drawn by their own apps, so NotificationNanny can only show them as live pictures of the real ones. That needs Screen Recording. Leave this off and widgets are simply left out.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
                    toggleRow("Show widgets", isOn: Binding(
                        get: { settings.customNotificationCenterWidgets },
                        set: { on in
                            settings.customNotificationCenterWidgets = on
                            if on, !permission.isGranted { permission.request() }
                        }
                    ))
                    if settings.customNotificationCenterWidgets {
                        Divider().padding(.leading, 14)
                        permissionRow
                    }
                }
            }
        }
        .onAppear { permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
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
                    LocalizedText("Allow NotificationNanny in System Settings. If you just did, quit and reopen NotificationNanny: macOS only applies it after a restart.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if !permission.isGranted {
                Button(loc.string("Open System Settings")) { permission.openSystemSettings() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func animationChip(_ anim: BannerAnimation) -> some View {
        let selected = settings.customNotificationCenterAnimation == anim
        return Button {
            settings.customNotificationCenterAnimation = anim
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

    @ViewBuilder
    private func section<Content: View>(_ titleKey: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(titleKey)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).kerning(0.5)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(Color.nannyRaised(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func toggleRow(_ labelKey: String, isOn: Binding<Bool>, detail: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                LocalizedText(labelKey).font(.callout)
                if let detail {
                    LocalizedText(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
