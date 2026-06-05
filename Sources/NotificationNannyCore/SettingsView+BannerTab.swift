import SwiftUI
import AppKit

struct BannerTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner

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
            // Experimental disclaimer
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

            // Scale
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

            // Background color
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

            // Animation
            VStack(alignment: .leading, spacing: 10) {
                Text("Appear Animation").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(BannerAnimation.allCases, id: \.self) { anim in
                        AnimationPreviewButton(anim: anim, isSelected: settings.bannerAnimation == anim) {
                            settings.bannerAnimation = anim
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            // Per-group overrides
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
            $0.bannerScale != nil || $0.hasBannerColor
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
                        settings.appGroups.first(where: { $0.id == group.id })?.bannerTint?.color
                            ?? settings.bannerColor
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
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
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

// MARK: - Animation preview button

private struct AnimationPreviewButton: View {
    let anim: BannerAnimation
    let isSelected: Bool
    let onTap: () -> Void

    @State private var shown = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)).frame(width: 42, height: 26)
                    pill
                }
                .clipped()
                Text(anim.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.nannyAccent : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? Color.nannyAccent.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .task {
            while !Task.isCancelled {
                shown = false
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(curve) { shown = true }
                try? await Task.sleep(for: .milliseconds(1850))
            }
        }
    }

    @ViewBuilder private var pill: some View {
        let c = isSelected ? Color.nannyAccent.opacity(0.85) : Color.white.opacity(0.4)
        switch anim {
        case .default:
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 30, height: 7).offset(x: shown ? 0 : 18)
        case .slide, .bounce:
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 30, height: 7).offset(y: shown ? 0 : -18)
        case .fade:
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 30, height: 7).opacity(shown ? 1 : 0)
        case .scale:
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 30, height: 7)
                .scaleEffect(shown ? 1 : 0.55).opacity(shown ? 1 : 0)
        }
    }

    private var curve: Animation {
        switch anim {
        case .default: return .spring(response: 0.45, dampingFraction: 0.85)
        case .slide:   return .spring(response: 0.45, dampingFraction: 0.78)
        case .bounce:  return .spring(response: 0.38, dampingFraction: 0.42)
        case .fade:    return .easeOut(duration: 0.3)
        case .scale:   return .spring(response: 0.38, dampingFraction: 0.68)
        }
    }
}
