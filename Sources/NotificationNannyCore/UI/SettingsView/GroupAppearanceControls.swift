import SwiftUI
import AppKit

/// Scale, tint and animation for one group, as a single compact row.
///
/// These used to live in the Banner tab as a stacked list of every group, which
/// split a group's settings across two tabs: position, screen and apps in
/// Exceptions, appearance over in Banner. The Exceptions blurb even promised
/// "position, screen, banner type, and scale" while only offering the first two.
/// Selecting a group now shows everything about that group in one place, and the
/// Banner tab is left to do one job — the global defaults these override.
struct GroupAppearanceControls: View {
    let groupID: UUID

    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var loc = LocalizationManager.shared

    private var group: AppGroup? { settings.appGroups.first(where: { $0.id == groupID }) }

    private var hasCustom: Bool {
        guard let group else { return false }
        return group.bannerScale != nil || group.hasBannerColor || group.bannerAnimation != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            LocalizedText("Appearance")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)

            if hasCustom {
                Slider(value: scaleBinding, in: 0.5...2.5)
                    // Snap to exactly 100%: without this the slider settles on
                    // 0.99-ish and the group counts as customised forever.
                    .onChange(of: scaleBinding.wrappedValue) { _, v in
                        if abs(v - 1.0) < 0.02 { scaleBinding.wrappedValue = 1.0 }
                    }
                    .controlSize(.mini)
                    .frame(minWidth: 70)
                Text("\(Int(scaleBinding.wrappedValue * 100))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                ColorPicker("", selection: tintBinding, supportsOpacity: false)
                    .labelsHidden()
                    .help(loc.string("Banner tint for this group"))
                animationMenu
                Button(loc.string("Reset")) {
                    update {
                        $0.bannerScale = nil
                        $0.bannerTint = nil
                        $0.bannerAnimation = nil
                    }
                }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
            } else {
                LocalizedText("Using default").font(.caption2).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button(loc.string("Customize")) {
                    update { $0.bannerScale = settings.bannerScale }
                }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
            }
        }
    }

    private var animationMenu: some View {
        let override = group?.bannerAnimation
        let effective = override ?? settings.bannerAnimation
        return Menu {
            Button { update { $0.bannerAnimation = nil } } label: {
                Label("Default (\(settings.bannerAnimation.label))", systemImage: "arrow.uturn.backward")
            }
            Divider()
            ForEach(BannerAnimation.allCases, id: \.self) { anim in
                Button { update { $0.bannerAnimation = anim } } label: {
                    Label(anim.label, systemImage: anim.iconName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: effective.iconName).font(.system(size: 9))
                Text(override == nil ? "Default" : effective.label).font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(loc.string("Animation for this group"))
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { group?.bannerScale ?? settings.bannerScale },
            set: { v in update { $0.bannerScale = v } }
        )
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { group?.bannerTint?.color ?? .white },
            set: { newColor in
                let c = NSColor(newColor).usingColorSpace(.sRGB) ?? .black
                update {
                    $0.bannerTint = BannerTint(r: Double(c.redComponent),
                                               g: Double(c.greenComponent),
                                               b: Double(c.blueComponent))
                }
            }
        )
    }

    /// One assignment to `appGroups` per edit, so observers never see a
    /// half-applied group.
    private func update(_ mutate: (inout AppGroup) -> Void) {
        guard let i = settings.appGroups.firstIndex(where: { $0.id == groupID }) else { return }
        var updated = settings.appGroups
        mutate(&updated[i])
        settings.appGroups = updated
    }
}
