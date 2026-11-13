import AppKit
import SwiftUI


/// A card: one setting, its title on top, a note under it.
struct SettingsCard<Content: View>: View {
    var spacing: CGFloat = 10
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCardBackground()
    }
}

extension View {
    /// The card's background alone, for a list of rows that sets its own padding.
    func settingsCardBackground() -> some View {
        background(Color.nannyCard, in: RoundedRectangle(cornerRadius: 10))
    }

    /// The room around a row in a list of rows, as on the General tab.
    func settingsListRow() -> some View {
        padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// A card's title, with whatever goes on its right: a reset, a picker.
struct SettingsCardHeader<Trailing: View>: View {
    let titleKey: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            LocalizedText(titleKey).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
    }
}

extension SettingsCardHeader where Trailing == EmptyView {
    init(_ titleKey: String) {
        self.init(titleKey: titleKey) { EmptyView() }
    }
}

/// The accent text button beside a card's title: Reset, Replay.
struct SettingsTextButton: View {
    let titleKey: String
    var disabled = false
    let action: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Button(loc.string(titleKey), action: action)
            .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
            .disabled(disabled)
    }
}

/// An action beside a card's title, with its icon: Replay, Play, Choose File.
struct CardActionButton: View {
    let titleKey: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { LocalizedText(titleKey) } icon: { Image(systemName: systemImage) }
                .font(.caption2)
        }
        .buttonStyle(.borderless).foregroundStyle(Color.nannyAccent)
    }
}

extension CardActionButton {
    static func replay(_ action: @escaping () -> Void) -> CardActionButton {
        CardActionButton(titleKey: "Replay", systemImage: "arrow.clockwise", action: action)
    }
}

/// The small print under a setting.
struct SettingsNote: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        LocalizedText(key).font(.caption2).foregroundStyle(Color.nannyNote)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A label with a switch on its right, and an optional line under the label.
struct SettingsToggleRow: View {
    let key: String
    @Binding var isOn: Bool
    var detail: String? = nil

    init(_ key: String, isOn: Binding<Bool>, detail: String? = nil) {
        self.key = key
        self._isOn = isOn
        self.detail = detail
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                LocalizedText(key).font(.callout)
                if let detail {
                    LocalizedText(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.nannySwitch).controlSize(.small)
        }
    }
}

/// The size slider, small A to large A, with its percentage.
struct SettingsScaleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 8) {
            Text("A").font(.caption2).foregroundStyle(.secondary)
            // Snap edits near 100% to exactly 1; do not save an inherited group value merely by
            // showing the slider.
            Slider(value: $value, in: range)
                .onChange(of: value) { _, v in if v != 1, abs(v - 1) < 0.02 { value = 1 } }
                .controlSize(.mini)
            Text("A").font(.body.weight(.medium)).foregroundStyle(.secondary)
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: Choices

struct AnimationChip: View {
    let animation: BannerAnimation
    let selected: Bool
    let action: () -> Void

    var body: some View {
        ChoiceChip(title: animation.label, systemImage: animation.iconName, selected: selected, action: action)
    }
}

/// One choice in a grid of them, its icon before it: an animation, a sound.
struct ChoiceChip<Icon: View>: View {
    /// Already localized, or a name of its own.
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon().font(.system(size: 10))
                Text(title).font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.nannyProminent.opacity(0.9) : Color.nannyRaised(0.06),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ChoiceChip where Icon == EmptyView {
    /// Choices without a distinguishing icon.
    init(title: String, selected: Bool, action: @escaping () -> Void) {
        self.init(title: title, selected: selected, action: action) { EmptyView() }
    }
}

extension ChoiceChip where Icon == Image {
    init(title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) {
        self.init(title: title, selected: selected, action: action) { Image(systemName: systemImage) }
    }
}

/// Every animation as a chip, the chosen one lit; none is lit while a group follows
/// All apps.
struct AnimationChipGrid: View {
    let selected: BannerAnimation?
    let onPick: (BannerAnimation) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
            ForEach(BannerAnimation.allCases, id: \.self) { anim in
                AnimationChip(animation: anim, selected: selected == anim) { onPick(anim) }
            }
        }
    }
}

/// Inherited value chip, placed before explicit choices.
struct FollowChip: View {
    let titleKey: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LocalizedText(titleKey)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(selected ? Color.nannyProminent.opacity(0.9) : Color.nannyRaised(0.06),
                            in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// Custom segmented choices with the selected icon raised in amber.
struct NannySegmentedPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let titleKey: String
        var systemImage: String? = nil
    }

    @Binding var selection: Value
    let options: [Option]
    /// Small sits in a row beside its label; regular fills a card's width.
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in segment(options[i]) }
        }
        .padding(2)
        .background(Color.nannyInset(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.nannyRaised(0.06), lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: selection)
    }

    private func segment(_ option: Option) -> some View {
        let selected = option.value == selection
        return Button { selection = option.value } label: {
            HStack(spacing: 5) {
                if let symbol = option.systemImage {
                    Image(systemName: symbol)
                        .font(.system(size: compact ? 9 : 10, weight: .semibold))
                        .foregroundStyle(selected ? Color.nannyAccent : Color.secondary)
                }
                LocalizedText(option.titleKey)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(selected ? Color.nannyStrong : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 3 : 6)
            .frame(maxWidth: compact ? nil : .infinity)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.nannySegment)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Colours

enum SettingsColors {
    static let presets: [(String, Color)] = [
        ("Red",    Color(red: 1.0,  green: 0.23, blue: 0.19)),
        ("Orange", Color(red: 1.0,  green: 0.58, blue: 0.0)),
        ("Yellow", Color(red: 1.0,  green: 0.80, blue: 0.0)),
        ("Green",  Color(red: 0.20, green: 0.78, blue: 0.35)),
        ("Teal",   Color(red: 0.18, green: 0.67, blue: 0.78)),
        ("Blue",   Color(red: 0.0,  green: 0.48, blue: 1.0)),
        ("Purple", Color(red: 0.69, green: 0.32, blue: 0.87)),
        ("Pink",   Color(red: 1.0,  green: 0.18, blue: 0.33)),
    ]

    static func isMatch(_ a: Color, _ b: Color) -> Bool {
        let ca = NSColor(a).usingColorSpace(.sRGB)
        let cb = NSColor(b).usingColorSpace(.sRGB)
        guard let ca, let cb else { return false }
        return abs(ca.redComponent   - cb.redComponent)   < 0.03 &&
               abs(ca.greenComponent - cb.greenComponent) < 0.03 &&
               abs(ca.blueComponent  - cb.blueComponent)  < 0.03
    }

    static func tint(of color: Color) -> BannerTint {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return BannerTint(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
}

struct ColorSwatch<Fill: View>: View {
    let selected: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder var fill: () -> Fill

    var body: some View {
        Button(action: action) {
            fill()
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(selected ? Color.nannyStrong : Color.clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(help)
    }
}

/// A hollow swatch selects the system default without a separate reset action.
struct DefaultColorSwatch: View {
    let selected: Bool
    var helpKey = "Default"
    let action: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        ColorSwatch(selected: selected, help: loc.string(helpKey), action: action) {
            ZStack {
                Circle().fill(Color.nannyRaised(0.06))
                Circle().strokeBorder(Color.nannyRaised(0.35), lineWidth: 1).padding(selected ? 3 : 0)
                Rectangle().fill(Color.secondary)
                    .frame(width: 1.5, height: selected ? 12 : 16)
                    .rotationEffect(.degrees(45))
            }
        }
    }
}

/// Default, preset, and custom swatches; `leading` supplies an optional inherited choice.
struct ColorSwatchRow<Leading: View>: View {
    /// No colour of one's own is in use: the default swatch is ringed.
    let isDefault: Bool
    /// Only the explicit active color; nil for defaults or inheritance so unused picker colors do
    /// not appear selected.
    let current: Color?
    /// Off for a group, whose only alternative to a colour is following All apps.
    var showsDefault = true
    var showsPresets = true
    var defaultHelpKey = "Default"
    let onDefault: () -> Void
    let onPick: (Color) -> Void
    @ViewBuilder var leading: () -> Leading

    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 6) {
            leading()
            if showsDefault {
                DefaultColorSwatch(selected: isDefault, helpKey: defaultHelpKey, action: onDefault)
            }
            if showsPresets {
                ForEach(SettingsColors.presets, id: \.0) { name, color in
                    ColorSwatch(selected: current.map { SettingsColors.isMatch(color, $0) } == true,
                                help: loc.string(name), action: { onPick(color) }) {
                        Circle().fill(color)
                    }
                }
            }
            Spacer()
            HStack(spacing: 4) {
                LocalizedText("Custom").font(.system(size: 9)).foregroundStyle(.tertiary)
                ColorPicker("", selection: Binding(get: { current ?? Color(white: 0.5) }, set: onPick),
                            supportsOpacity: false).labelsHidden()
            }
            .help(loc.string("Pick any custom color"))
        }
    }
}

extension ColorSwatchRow where Leading == EmptyView {
    init(isDefault: Bool, current: Color?, showsPresets: Bool = true,
         defaultHelpKey: String = "Default",
         onDefault: @escaping () -> Void, onPick: @escaping (Color) -> Void) {
        self.init(isDefault: isDefault, current: current, showsPresets: showsPresets,
                  defaultHelpKey: defaultHelpKey, onDefault: onDefault, onPick: onPick) { EmptyView() }
    }
}

// MARK: Displays

/// Resolve saved displays by stable key without rewriting the saved choice.
/// Show disconnected displays explicitly; zero means automatic selection.
struct DisplayPicker: View {
    @Binding var selection: CGDirectDisplayID
    /// The display the saved choice comes to now, if any.
    let resolved: NSScreen?
    let zeroLabelKey: String
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        let shown = resolved?.displayID ?? selection
        var options = [NannyMenuPicker<CGDirectDisplayID>.Option(value: 0, title: loc.string(zeroLabelKey))]
        options += NSScreen.screens.map { .init(value: $0.displayID, title: $0.nannyDisplayName) }
        if selection != 0 && resolved == nil {
            options.append(.init(value: selection, title: loc.string("Disconnected display")))
        }
        return NannyMenuPicker(selection: Binding(
            get: { shown },
            set: { if $0 != shown { selection = $0 } }
        ), options: options, systemImage: "display")
    }
}

/// Compact menu pill sized to its selected label.
struct NannyMenuPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        /// Already localized.
        let title: String
    }

    @Binding var selection: Value
    let options: [Option]
    var systemImage: String? = nil

    var body: some View {
        let current = options.first { $0.value == selection }?.title ?? ""
        Menu {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                Button { selection = option.value } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10)).foregroundStyle(Color.nannyAccent)
                }
                Text(current).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(Color.nannyStrong)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.nannyRaised(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.nannyRaised(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: Buttons and switches

/// Keep the accent fill when Settings is unfocused.
struct NannyProminentButtonStyle: ButtonStyle {
    var fill: Color = .nannyProminent

    func makeBody(configuration: Configuration) -> some View {
        ProminentLabel(configuration: configuration, fill: fill)
    }

    private struct ProminentLabel: View {
        let configuration: Configuration
        let fill: Color
        @Environment(\.controlSize) private var size
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let (h, v, font): (CGFloat, CGFloat, Font) = switch size {
            case .mini: (7, 2, .caption2)
            case .small: (9, 3, .caption)
            default: (12, 6, .callout)
            }
            configuration.label
                .font(font.weight(.medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, h).padding(.vertical, v)
                .background(fill.opacity(configuration.isPressed ? 0.75 : 1),
                            in: RoundedRectangle(cornerRadius: size == .regular ? 7 : 5, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == NannyProminentButtonStyle {
    static var nannyProminent: NannyProminentButtonStyle { NannyProminentButtonStyle() }
}

/// A switch that stays amber when on, focused window or not; the system's goes grey.
struct NannySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration)
    }

    private struct SwitchBody: View {
        let configuration: Configuration
        @Environment(\.controlSize) private var size
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let on = configuration.isOn
            let track = size == .mini || size == .small ? CGSize(width: 28, height: 16) : CGSize(width: 34, height: 20)
            let knob = track.height - 4
            Capsule()
                .fill(on ? Color.nannySwitchOn : Color.nannyRaised(0.18))
                .frame(width: track.width, height: track.height)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(Color.white)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .padding(2)
                }
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.15), value: on)
                .contentShape(Capsule())
                .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
                .accessibilityRepresentation {
                    Toggle(isOn: configuration.$isOn) { configuration.label }
                }
        }
    }
}

extension ToggleStyle where Self == NannySwitchStyle {
    static var nannySwitch: NannySwitchStyle { NannySwitchStyle() }
}

// MARK: Position

/// Shared display and placement card for global and exception settings.
struct PositionCard: View {
    let titleKey: String
    let screen: NSScreen
    @Binding var display: CGDirectDisplayID
    /// The display the saved choice comes to now, if any.
    let resolvedDisplay: NSScreen?
    let zeroLabelKey: String
    @Binding var placement: ScreenPlacement
    var previewHeight: CGFloat = 260
    let noteKey: String

    /// Fit the preview to the measured inner width so narrow windows do not overflow.
    @State private var width: CGFloat = 400

    var body: some View {
        let visible = screen.visibleFrame
        SettingsCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LocalizedText(titleKey).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("\(Int(visible.width)) × \(Int(visible.height))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(Color.nannyNote)
                Spacer()
                if NSScreen.screens.count > 1 {
                    DisplayPicker(selection: $display, resolved: resolvedDisplay, zeroLabelKey: zeroLabelKey)
                }
            }
            Color.clear.frame(height: 0)
                .background(GeometryReader { g in
                    Color.clear.onAppear { width = g.size.width }
                        .onChange(of: g.size.width) { _, w in width = w }
                })
            // The device's frame and stand reach past the picture: keep room for them.
            PlacementEditor(screen: screen, placement: $placement,
                            maxWidth: max(200, width - 28), maxHeight: previewHeight)
            SettingsNote(noteKey)
        }
    }
}
