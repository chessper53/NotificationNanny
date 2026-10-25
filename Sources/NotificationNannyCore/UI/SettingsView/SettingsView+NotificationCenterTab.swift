import AppKit
import SwiftUI

/// The custom Notification Center's settings, laid out like the Banner tab: one card per
/// setting, its title on top, a note under it. Everything starts as macOS has it; the
/// extras that macOS doesn't have start off.
struct NotificationCenterTabView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var permission = ScreenRecordingPermission.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var previewReplay = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                HStack {
                    LocalizedText("Notification Center").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: $settings.customNotificationCenter)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                LocalizedText("Use NotificationNanny's Notification Center (experimental)").font(.callout)
                note("NotificationNanny can show its own list when you click the clock, in place of the Notification Center panel. Your notifications stay in Notification Center: this is another view of them, and everything you do in it goes back there.")
            }

            if settings.customNotificationCenter {
                sizeCard
                positionCard
                animationCard
                card {
                    LocalizedText("Look").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    note("Rows look like your banners: their colour, text colour and privacy blur come from the Banner tab and your exceptions.")
                }
                extrasCard
                widgetsCard

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

    private var positionCard: some View {
        card {
            LocalizedText("Position").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Picker("", selection: $settings.customNotificationCenterSide) {
                ForEach(NCPanelSide.allCases) { Text(loc.string($0.labelKey)).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            // The same setting as General's "Don't move Notification Center", which means
            // the same for the system's panel.
            Picker("", selection: $settings.avoidNCPanel) {
                Text(loc.string("Where you click the clock")).tag(true)
                Text(loc.string("Where your banners go")).tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()
            note(settings.customNotificationCenterSide == .right && settings.avoidNCPanel
                 ? "As macOS: on the right, on the screen whose clock you click."
                 : "The side of the screen, and which screen it opens on.")
        }
    }

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
                                 tint: settings.hasBannerColor ? settings.bannerColor : .clear,
                                 textColor: settings.effectiveBannerTextColor ?? .primary)
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

    private var extrasCard: some View {
        card {
            LocalizedText("Extras").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            toggleRow("Show when notifications arrived", isOn: $settings.customNotificationCenterTimes)
            toggleRow("Filter by app", isOn: $settings.customNotificationCenterAppFilter)
            note("Not part of macOS's Notification Center, so off unless you turn them on. Times are noted when each banner appears; notifications that came in while NotificationNanny wasn't running have none.")
        }
    }

    private var widgetsCard: some View {
        card {
            HStack {
                LocalizedText("Widgets").font(.caption.weight(.medium)).foregroundStyle(.secondary)
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
            note("Widgets are drawn by their own apps, so NotificationNanny can only show them as live pictures of the real ones. That needs Screen Recording. Leave this off and widgets are simply left out.")
            if settings.customNotificationCenterWidgets {
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
        }
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
