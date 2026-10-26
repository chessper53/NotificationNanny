import SwiftUI
import AppKit

struct BannerTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @State private var previewReplay = 0

    /// The group being edited, nil for All apps.
    @State private var scope: UUID?

    init(initialScope: UUID? = nil) {
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BannerScopeBar(groupID: $scope)
            if let scope, settings.group(by: scope) != nil {
                // Its own identity per group, so nothing carries over from one to the next.
                BannerGroupEditor(groupID: scope).id(scope)
            } else {
                allApps
            }
        }
        .onChange(of: settings.appGroups) { _, groups in
            if let id = scope, !groups.contains(where: { $0.id == id }) { scope = nil }
        }
    }

    private var allApps: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsCardHeader(titleKey: "Default Scale") {
                    SettingsTextButton(titleKey: "Reset", disabled: abs(settings.bannerScale - 1.0) < 0.01) {
                        settings.bannerScale = 1.0
                    }
                }
                SettingsScaleSlider(value: $settings.bannerScale, range: 0.5...2.5)
            }

            SettingsCard {
                SettingsCardHeader("Background Color")
                ColorSwatchRow(isDefault: !settings.hasBannerColor,
                               current: settings.hasBannerColor ? settings.bannerColor : nil,
                               onDefault: { settings.clearBannerColor() },
                               onPick: { settings.bannerColor = $0 })
                SettingsNote(settings.hasBannerColor ? "Tint active. Custom renderer on" : "No tint")
            }

            SettingsCard {
                SettingsCardHeader("Text Color")
                ColorSwatchRow(isDefault: !settings.hasBannerTextColor,
                               current: settings.bannerTextTint?.color,
                               showsPresets: false,
                               onDefault: { settings.clearBannerTextColor() },
                               onPick: { settings.bannerTextTint = SettingsColors.tint(of: $0) })
                SettingsNote(settings.hasBannerTextColor
                             ? "Custom text color active. Custom renderer on"
                             : "Default. Follows system appearance")
            }

            SettingsCard {
                SettingsCardHeader(titleKey: "Animation") {
                    CardActionButton.replay { previewReplay &+= 1 }
                }
                AnimationPreviewPane(animation: settings.bannerAnimation, replay: previewReplay,
                                     tint: settings.hasBannerColor ? settings.bannerColor : .clear,
                                     textColor: settings.effectiveBannerTextColor ?? .primary)
                    .animationPreviewWell { previewReplay &+= 1 }
                AnimationChipGrid(selected: settings.bannerAnimation) {
                    settings.bannerAnimation = $0
                    previewReplay &+= 1
                }
                SettingsNote(settings.bannerAnimation == .default
                             ? "System-style slide-in. Other animations activate the custom renderer."
                             : "Custom animation active. Replaces the system banner.")
            }

            SettingsCard {
                SettingsCardHeader("Stacking")
                NannySegmentedPicker(selection: $settings.newestBannerAtBottom, options: [
                    .init(value: false, titleKey: "Newest on top", systemImage: "arrow.up.to.line"),
                    .init(value: true, titleKey: "Newest at the bottom", systemImage: "arrow.down.to.line"),
                ])
                SettingsNote("Order of notifications that are up together. Custom banner only: macOS stacks its own banner newest on top.")
            }

            Button { repositioner.sendTestNotification(groupID: nil) } label: {
                Label {
                    LocalizedText("Send Test Notification")
                } icon: {
                    Image(systemName: "paperplane.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.nannyProminent).controlSize(.regular)
        }
    }
}

extension AnimationPreviewPane {
    /// The recessed well the sample plays in; a click plays it again.
    func animationPreviewWell(replay: @escaping () -> Void) -> some View {
        frame(height: 64)
            .frame(maxWidth: .infinity)
            .background(Color.nannyInset(0.22), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onTapGesture(perform: replay)
    }
}

/// A sample banner playing an animation; shared with the Notification Center tab.
struct AnimationPreviewPane: View {
    let animation: BannerAnimation
    let replay: Int
    var tint: Color = .clear
    /// `.primary` unless the user picked a text colour, so the sample reads like the
    /// real banner: dark lines on a light banner in Light Mode, light lines in Dark Mode.
    var textColor: Color = .primary

    @State private var animX: CGFloat = 0
    @State private var animY: CGFloat = 0
    @State private var animOpacity: Double = 1
    @State private var animScale: CGFloat = 1
    @State private var animRotation: Double = 0

    var body: some View {
        sample
            .opacity(animOpacity)
            .scaleEffect(animScale)
            .rotationEffect(.degrees(animRotation))
            .offset(x: animX, y: animY)
            .onAppear { play() }
            .onChange(of: replay) { _, _ in play() }
            .onChange(of: animation) { _, _ in play() }
    }

    private var sample: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.nannyRaised(0.25)).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(textColor.opacity(0.85)).frame(width: 64, height: 6)
                RoundedRectangle(cornerRadius: 3).fill(textColor.opacity(0.55)).frame(width: 104, height: 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 220)
        .background {
            ZStack {
                // The system banner is dark glass in Dark Mode and light glass in Light Mode.
                Color.nannyAdaptive(light: .white.withAlphaComponent(0.85), dark: .black.withAlphaComponent(0.5))
                if tint != .clear { tint.opacity(0.45) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func play() {
        let h = animation.hidden
        animX = h.x; animY = h.y; animOpacity = h.opacity; animScale = h.scale; animRotation = h.rotation
        withAnimation(animation.intro) {
            animX = 0; animY = 0; animOpacity = 1; animScale = 1; animRotation = 0
        }
    }
}
