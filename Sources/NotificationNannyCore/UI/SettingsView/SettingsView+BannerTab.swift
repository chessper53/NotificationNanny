import SwiftUI
import AppKit

struct BannerTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner

    @State private var previewReplay = 0

    private static let colorPresets: [(String, Color)] = [
        ("Red",    Color(red: 1.0,  green: 0.23, blue: 0.19)),
        ("Orange", Color(red: 1.0,  green: 0.58, blue: 0.0)),
        ("Yellow", Color(red: 1.0,  green: 0.80, blue: 0.0)),
        ("Green",  Color(red: 0.20, green: 0.78, blue: 0.35)),
        ("Teal",   Color(red: 0.18, green: 0.67, blue: 0.78)),
        ("Blue",   Color(red: 0.0,  green: 0.48, blue: 1.0)),
        ("Purple", Color(red: 0.69, green: 0.32, blue: 0.87)),
        ("Pink",   Color(red: 1.0,  green: 0.18, blue: 0.33)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "flask")
                    .font(.caption).foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.0)).padding(.top, 1)
                Text("Experimental. The custom banner replaces the system one entirely. Some notification actions like inline replies may not work. Behavior can vary between apps and macOS versions.")
                    .font(.caption).foregroundStyle(Color(white: 0.75)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 1)
                Text("Custom renderer activates automatically when scale ≠ 100%, a tint color is set, or banner mode is forced. It replaces the system banner with a custom one that supports scaling, tinting, and animation.")
                    .font(.caption).foregroundStyle(Color(white: 0.6)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Default Scale").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { settings.bannerScale = 1.0 }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                        .disabled(abs(settings.bannerScale - 1.0) < 0.01)
                }
                HStack(spacing: 8) {
                    Text("A").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $settings.bannerScale, in: 0.5...2.5)
                        .onChange(of: settings.bannerScale) { _, v in if abs(v - 1.0) < 0.02 { settings.bannerScale = 1.0 } }
                        .controlSize(.mini)
                    Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    Text("\(Int(settings.bannerScale * 100))%")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Background Color").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { settings.clearBannerColor() }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                        .disabled(!settings.hasBannerColor)
                }
                HStack(spacing: 6) {
                    ForEach(Self.colorPresets, id: \.0) { name, color in
                        Button { settings.bannerColor = color } label: {
                            Circle().fill(color).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(
                                    settings.hasBannerColor && isColorMatch(color, settings.bannerColor)
                                        ? Color.white : Color.clear,
                                    lineWidth: 2))
                        }
                        .buttonStyle(.plain).help(name)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Custom").font(.system(size: 9)).foregroundStyle(.tertiary)
                        ColorPicker("", selection: Binding(
                            get: { settings.bannerColor },
                            set: { settings.bannerColor = $0 }
                        ), supportsOpacity: false).labelsHidden()
                    }
                    .help("Pick any custom color")
                }
                Text(settings.hasBannerColor ? "Tint active — custom renderer on" : "No tint")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Text Color").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { settings.clearBannerTextColor() }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                        .disabled(!settings.hasBannerTextColor)
                }
                HStack(spacing: 8) {
                    ColorPicker("Text", selection: Binding(
                        get: { settings.bannerTextTint?.color ?? .black },
                        set: { newColor in
                            let color = NSColor(newColor).usingColorSpace(.sRGB) ?? .black
                            settings.bannerTextTint = BannerTint(
                                r: Double(color.redComponent),
                                g: Double(color.greenComponent),
                                b: Double(color.blueComponent))
                        }
                    ), supportsOpacity: false)
                    Spacer()
                }
                Text(settings.hasBannerTextColor
                     ? "Custom text color active — custom renderer on"
                     : "Default — follows system appearance")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Animation").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        previewReplay &+= 1
                    } label: {
                        Label("Replay", systemImage: "arrow.clockwise").font(.caption2)
                    }
                    .buttonStyle(.borderless).foregroundStyle(Color.nannyAccent)
                }

                AnimationPreviewPane(animation: settings.bannerAnimation, replay: previewReplay,
                                     tint: settings.hasBannerColor ? settings.bannerColor : .clear,
                                     textColor: settings.effectiveBannerTextColor ?? .white)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture { previewReplay &+= 1 }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
                    ForEach(BannerAnimation.allCases, id: \.self) { anim in
                        animationChip(anim)
                    }
                }

                Text(settings.bannerAnimation == .default
                     ? "System-style slide-in. Other animations activate the custom renderer."
                     : "Custom animation active — replaces the system banner.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            if !settings.appGroups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-app overrides").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(settings.appGroups) { group in
                            groupScaleRow(for: group)
                            if group.id != settings.appGroups.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            Button { repositioner.sendTestNotification(groupID: nil) } label: {
                Label("Send Test Notification", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.regular)
        }
    }

    @ViewBuilder
    private func groupScaleRow(for group: AppGroup) -> some View {
        let hasCustom = settings.appGroups.first(where: { $0.id == group.id }).map {
            $0.bannerScale != nil || $0.hasBannerColor || $0.bannerAnimation != nil
        } ?? false
        let scaleBinding = Binding<Double>(
            get: { settings.appGroups.first(where: { $0.id == group.id })?.bannerScale ?? settings.bannerScale },
            set: { v in
                guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                settings.appGroups[i].bannerScale = v
            }
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name).font(.callout)
                Spacer()
                if hasCustom {
                    Button("Reset") {
                        guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                        settings.appGroups[i].bannerScale = nil
                        settings.appGroups[i].bannerTint  = nil
                        settings.appGroups[i].bannerAnimation = nil
                    }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                } else {
                    Text("Using default").font(.caption2).foregroundStyle(.tertiary)
                    Button("Customize") {
                        guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                        settings.appGroups[i].bannerScale = settings.bannerScale
                    }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                }
            }
            if hasCustom {
                HStack(spacing: 8) {
                    Text("A").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: scaleBinding, in: 0.5...2.5)
                        .onChange(of: scaleBinding.wrappedValue) { _, v in if abs(v - 1.0) < 0.02 { scaleBinding.wrappedValue = 1.0 } }
                        .controlSize(.mini)
                    Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    Text("\(Int(scaleBinding.wrappedValue * 100))%")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                }
                let colorBinding = Binding<Color>(
                    get: {
                        settings.appGroups.first(where: { $0.id == group.id })?.bannerTint?.color ?? .white
                    },
                    set: { newColor in
                        guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                        let c = NSColor(newColor).usingColorSpace(.sRGB) ?? .black
                        settings.appGroups[i].bannerTint = BannerTint(
                            r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
                    }
                )
                HStack(spacing: 8) {
                    Text("Color").font(.caption2).foregroundStyle(.secondary)
                    ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden()
                    if settings.appGroups.first(where: { $0.id == group.id })?.hasBannerColor == true {
                        Button("Clear") {
                            guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
                            settings.appGroups[i].bannerTint = nil
                        }
                        .buttonStyle(.borderless).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    groupAnimationMenu(for: group)
                    Button { repositioner.sendTestNotification(groupID: group.id) } label: {
                        Label("Test", systemImage: "paperplane.fill").font(.caption2)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func groupAnimationMenu(for group: AppGroup) -> some View {
        let override = settings.appGroups.first(where: { $0.id == group.id })?.bannerAnimation
        let effective = override ?? settings.bannerAnimation
        let setAnimation: (BannerAnimation?) -> Void = { anim in
            guard let i = settings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
            settings.appGroups[i].bannerAnimation = anim
        }
        Menu {
            Button { setAnimation(nil) } label: {
                Label("Default (\(settings.bannerAnimation.label))", systemImage: "arrow.uturn.backward")
            }
            Divider()
            ForEach(BannerAnimation.allCases, id: \.self) { anim in
                Button { setAnimation(anim) } label: { Label(anim.label, systemImage: anim.iconName) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: effective.iconName).font(.system(size: 9))
                Text(override == nil ? "Default" : effective.label).font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Animation for this group")
    }

    @ViewBuilder
    private func animationChip(_ anim: BannerAnimation) -> some View {
        let selected = settings.bannerAnimation == anim
        Button {
            settings.bannerAnimation = anim
            previewReplay &+= 1
        } label: {
            HStack(spacing: 5) {
                Image(systemName: anim.iconName).font(.system(size: 10))
                Text(anim.label).font(.caption)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.nannyAccent.opacity(0.9) : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func isColorMatch(_ a: Color, _ b: Color) -> Bool {
        let ca = NSColor(a).usingColorSpace(.sRGB)
        let cb = NSColor(b).usingColorSpace(.sRGB)
        guard let ca, let cb else { return false }
        return abs(ca.redComponent   - cb.redComponent)   < 0.03 &&
               abs(ca.greenComponent - cb.greenComponent) < 0.03 &&
               abs(ca.blueComponent  - cb.blueComponent)  < 0.03
    }
}

private struct AnimationPreviewPane: View {
    let animation: BannerAnimation
    let replay: Int
    var tint: Color = .clear
    var textColor: Color = .white

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
                .fill(Color.white.opacity(0.25)).frame(width: 26, height: 26)
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
                Color.black.opacity(0.5)
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
