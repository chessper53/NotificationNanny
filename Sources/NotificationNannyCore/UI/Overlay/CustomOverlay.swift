import AppKit
import SwiftUI
import UniformTypeIdentifiers

package enum BannerAnimation: String, Codable, CaseIterable {
    case `default`  = "Default"
    case fade       = "Fade"
    case scale      = "Scale"
    case bounce     = "Bounce"
    case drop       = "Drop"
    case slideLeft  = "SlideLeft"
    case rise       = "Rise"
    case swing      = "Swing"

    package var label: String {
        switch self {
        case .slideLeft: return "Slide"
        default:         return rawValue
        }
    }

    package var iconName: String {
        switch self {
        case .default:   return "arrow.left"
        case .fade:      return "circle.dotted"
        case .scale:     return "arrow.up.left.and.arrow.down.right"
        case .bounce:    return "arrow.up.circle"
        case .drop:      return "arrow.down"
        case .slideLeft: return "arrow.right"
        case .rise:      return "arrow.up"
        case .swing:     return "wind"
        }
    }

    struct Transform: Equatable {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var opacity: Double = 1
        var scale: CGFloat = 1
        var rotation: Double = 0
    }

    /// One animation specification supplies every intro and outro transform.
    struct Spec {
        let hidden: Transform
        let intro: Animation
        let outro: Animation
        let outroDuration: Double
    }

    var spec: Spec {
        switch self {
        case .default:
            return Spec(hidden: Transform(x: 150),
                        intro: .spring(response: 0.45, dampingFraction: 0.78),
                        outro: .spring(response: 0.35, dampingFraction: 0.85),
                        outroDuration: 0.38)
        case .fade:
            return Spec(hidden: Transform(opacity: 0),
                        intro: .easeOut(duration: 0.35),
                        outro: .easeIn(duration: 0.22),
                        outroDuration: 0.24)
        case .scale:
            return Spec(hidden: Transform(opacity: 0, scale: 0.8),
                        intro: .spring(response: 0.40, dampingFraction: 0.72),
                        outro: .easeIn(duration: 0.20),
                        outroDuration: 0.24)
        case .bounce:
            return Spec(hidden: Transform(opacity: 0, scale: 0.5),
                        intro: .spring(response: 0.50, dampingFraction: 0.55),
                        outro: .easeIn(duration: 0.20),
                        outroDuration: 0.24)
        case .drop:
            return Spec(hidden: Transform(y: -120),
                        intro: .spring(response: 0.50, dampingFraction: 0.70),
                        outro: .easeIn(duration: 0.22),
                        outroDuration: 0.24)
        case .slideLeft:
            return Spec(hidden: Transform(x: -150),
                        intro: .spring(response: 0.45, dampingFraction: 0.80),
                        outro: .easeIn(duration: 0.22),
                        outroDuration: 0.24)
        case .rise:
            return Spec(hidden: Transform(y: 120, opacity: 0),
                        intro: .spring(response: 0.48, dampingFraction: 0.78),
                        outro: .easeIn(duration: 0.22),
                        outroDuration: 0.24)
        case .swing:
            return Spec(hidden: Transform(opacity: 0, scale: 0.9, rotation: -8),
                        intro: .spring(response: 0.50, dampingFraction: 0.52),
                        outro: .easeIn(duration: 0.22),
                        outroDuration: 0.24)
        }
    }

    var hidden: Transform { spec.hidden }
    var intro: Animation { spec.intro }
    var outro: Animation { spec.outro }
    var outroDuration: Double { spec.outroDuration }
}

struct BannerContent: Equatable {
    let appName: String
    let title: String
    var subtitle: String = ""
    let body: String
    let appIcon: NSImage?
    /// The app's own buttons on the real banner (Reply, Archive…); see NotificationActions.
    var actions: [String] = []
    /// The real banner shows its buttons ("Show Details" was used).
    var expanded = false
    /// What is typed in the real banner's open reply field; nil while none is open.
    var reply: String? = nil
    var replyPlaceholder = ""
    /// Notification Center's time for a panel row ("27m ago"), drawn at the end of the
    /// title's line; nil on banners.
    var time: String? = nil

    static func == (l: BannerContent, r: BannerContent) -> Bool {
        l.appName == r.appName && l.title == r.title && l.subtitle == r.subtitle && l.body == r.body
            && l.actions == r.actions && l.expanded == r.expanded && l.reply == r.reply && l.time == r.time
    }
}

/// Measured banner appearance; PROD lab builds override values with NN_LOOK_<NAME>.
enum BannerLook {
    private static func value(_ name: String, _ measured: Double) -> Double {
        #if PROD
        if let v = ProcessInfo.processInfo.environment["NN_LOOK_" + name].flatMap(Double.init) { return v }
        #endif
        return measured
    }
    /// No light wash: ordinary white opacity would dim the backdrop instead of brightening it.
    static var lightWash: Double { value("LIGHT_WASH", 0) }
    /// Reduce light glass opacity to match native backdrop transmission; see lightAdd.
    static var lightGlassOpacity: Double { value("LIGHT_GLASS", 0.92) }
    /// Add white with plusLighter to brighten without dimming the backdrop.
    static var lightAdd: Double { value("LIGHT_ADD", 0.037) }
    /// Inner bright rim opacity shared by both appearances.
    static var rim: Double { value("RIM", 0.25) }
    /// The hairline above each of the app's buttons when the details are shown.
    static var divider: Double { value("DIVIDER", 0.12) }
    /// The Options pill shown on hover.
    static var pill: Double { value("PILL", 0.12) }
    /// The reply field's fill and edge.
    static var field: Double { value("FIELD", 0.25) }
    static var fieldEdge: Double { value("FIELD_EDGE", 0.22) }
    /// A lab build can show the hover state without a pointer, to measure it.
    static var forceHover: Bool { value("HOVER", 0) > 0 }
    /// The dark line just outside the edge, Light Mode only.
    static var lightLine: Double { value("LIGHT_LINE", 0.08) }
}

@MainActor
final class BannerAnimationController {
    var slideOutClosure: (() -> Void)?
    var dismissCompletion: (() -> Void)?
}

struct CustomBannerView: View {
    /// Mutable so the overlay follows the real banner as it opens its buttons or a reply.
    var content: BannerContent
    /// Redraw at the new scale rather than stretching a previous render.
    var scale: CGFloat
    let animation: BannerAnimation
    let tint: Color
    let textColor: Color?
    let redactContent: Bool
    let controller: BannerAnimationController
    let onDismiss: () -> Void
    let onOpen: () -> Void
    let onAction: (String) -> Void
    let onDetails: () -> Void
    var menuSource: BannerMenuSource? = nil

    @State private var animX: CGFloat
    @State private var animY: CGFloat
    @State private var animOpacity: Double
    @State private var animScale: CGFloat
    @State private var animRotation: Double
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    private var isLight: Bool { colorScheme == .light }
    @State private var animationsSetup = false
    @State private var cursorPushed = false

    init(content: BannerContent, scale: CGFloat, animation: BannerAnimation, tint: Color,
         textColor: Color?, redactContent: Bool = false, controller: BannerAnimationController,
         onDismiss: @escaping () -> Void, onOpen: @escaping () -> Void,
         onAction: @escaping (String) -> Void = { _ in }, onDetails: @escaping () -> Void = {}) {
        self.content = content
        self.scale = scale
        self.animation = animation
        self.tint = tint
        self.textColor = textColor
        self.redactContent = redactContent
        self.controller = controller
        self.onDismiss = onDismiss
        self.onOpen = onOpen
        self.onAction = onAction
        self.onDetails = onDetails
        let h = animation.hidden
        _animX = State(initialValue: h.x)
        _animY = State(initialValue: h.y)
        _animOpacity = State(initialValue: h.opacity)
        _animScale = State(initialValue: h.scale)
        _animRotation = State(initialValue: h.rotation)
    }

    /// Native macOS 27 geometry in points; multiply by scale at use sites.
    enum Metrics {
        static let cornerRadius: CGFloat = 20
        /// The 38 point icon frame includes app artwork padding, leaving a visible 31 point icon.
        static let iconFrame: CGFloat = 38
        static let iconLeading: CGFloat = 10
        /// Text starts 58pt from the leading edge: 10 + 38 + 10.
        static let iconTextSpacing: CGFloat = 10
        static let textTop: CGFloat = 12
        static let textBottom: CGFloat = 13
        static let textTrailing: CGFloat = 14
        static let lineSpacing: CGFloat = 1
        static let fontSize: CGFloat = 13
        /// A faint white wash matches native brightness across backdrops.
        static let wash: Double = 0.05
        /// Grow the panel margins to fit the close button overhanging the card.
        static let closeDiameter: CGFloat = 20
        /// Native close button origin relative to the banner, including its corner overhang.
        static let closeOrigin = CGPoint(x: -6, y: -4)
        static let chromeInset: CGFloat = 8
    }

    var body: some View {
        let inset = Metrics.chromeInset * scale
        banner
            .overlay(alignment: .topLeading) {
                if isHovered || BannerLook.forceHover {
                    closeButton
                        .offset(x: Metrics.closeOrigin.x * scale, y: Metrics.closeOrigin.y * scale)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(inset)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
                setCursorPushed(hovering)
            }
            // onHover only reports while the app is active, which it never is here.
            .activeHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            }
            .onDisappear { setCursorPushed(false) }
            .opacity(animOpacity)
            .scaleEffect(animScale)
            .rotationEffect(.degrees(animRotation))
            .offset(x: animX, y: animY)
            .onAppear {
                guard !animationsSetup else { return }
                animationsSetup = true
                setupAnimations()
            }
    }

    private var banner: some View {
        BannerCard(content: content, scale: scale, tint: tint, textColor: textColor,
                   redactContent: redactContent, hovered: isHovered,
                   onOpen: onOpen, onAction: onAction, onDetails: onDetails, menuSource: menuSource)
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            ZStack {
                BannerBackground(cornerRadius: Metrics.closeDiameter / 2 * scale)
                Image(systemName: "xmark")
                    .font(.system(size: 8 * scale, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: Metrics.closeDiameter * scale, height: Metrics.closeDiameter * scale)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func setupAnimations() {
        let hidden = animation.hidden
        controller.slideOutClosure = {
            withAnimation(animation.outro) { apply(hidden) }
            scheduleDismiss(after: animation.outroDuration)
        }
        withAnimation(animation.intro) { apply(.init()) }
    }

    private func setCursorPushed(_ pushed: Bool) {
        guard pushed != cursorPushed else { return }
        cursorPushed = pushed
        if pushed { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    private func apply(_ t: BannerAnimation.Transform) {
        animX = t.x; animY = t.y; animOpacity = t.opacity; animScale = t.scale; animRotation = t.rotation
    }

    private func scheduleDismiss(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak controller] in
            controller?.dismissCompletion?()
        }
    }
}

/// Shared native style card for custom banners and panel rows.
struct BannerCard: View {
    let content: BannerContent
    let scale: CGFloat
    let tint: Color
    let textColor: Color?
    var redactContent = false
    /// Under the pointer: shows the more menu and the chevron, as the system's does.
    var hovered = false
    /// A row of the Notification Center panel rather than a banner; see GlassEdge.
    var edge: GlassEdge = .banner
    var onOpen: () -> Void = {}
    var onAction: (String) -> Void = { _ in }
    var onDetails: () -> Void = {}
    /// Let the owner draw menus using button frames; a separate menu window would close the native
    /// panel.
    /// Without callbacks, Options uses its own menu and the more button is decorative.
    var onMore: ((CGRect) -> Void)? = nil
    var onOptions: ((CGRect) -> Void)? = nil
    /// Native menu source for a custom banner's more button.
    var menuSource: BannerMenuSource? = nil

    @Environment(\.colorScheme) private var colorScheme
    private var isLight: Bool { colorScheme == .light }
    @State private var menuAnchor: MenuAnchor = MenuAnchor()
    @State private var pillFrame: CGRect = .zero
    @State private var moreAnchor: MenuAnchor = MenuAnchor()

    typealias Metrics = CustomBannerView.Metrics

    /// Native hover controls: Options and a chevron, replaced by more and the expanded chevron with
    /// details.
    @ViewBuilder private var chrome: some View {
        let showDetails = content.expanded || hovered || BannerLook.forceHover
        if showDetails {
            ZStack(alignment: .topLeading) {
                Button(action: onDetails) {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(content.expanded ? 90 : 0))
                        .frame(width: chevron.width * scale, height: chevron.height * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizationManager.shared.string("Options"))
                .offset(x: chevron.minX * scale, y: chevron.minY * scale)
                if content.expanded {
                    let more = Expanded.moreFrame
                    let moreFrame = CGRect(x: more.minX * scale, y: more.minY * scale,
                                           width: more.width * scale, height: more.height * scale)
                    Button {
                        if let onMore {
                            onMore(moreFrame)
                        } else if let menuSource {
                            menuSource.items(false) { [moreAnchor] items in moreAnchor.popUp(items, menuSource.choose) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11 * scale, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: moreFrame.width, height: moreFrame.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizationManager.shared.string("More"))
                    .background(MenuAnchorView(anchor: moreAnchor))
                    .offset(x: moreFrame.minX, y: moreFrame.minY)
                } else {
                    // Bottom right, on the last line of text, whatever the card's height.
                    optionsMenu
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { pillFrame = g.frame(in: .named(Self.space)) }
                                .onChange(of: g.frame(in: .named(Self.space))) { _, f in pillFrame = f }
                        })
                        .padding(.trailing, Hovered.optionsInset * scale)
                        .padding(.bottom, Hovered.optionsInset * scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .transition(.opacity)
        }
    }

    private var chevron: CGRect { content.expanded ? Expanded.chevronFrame : Hovered.chevron }

    /// Options and the app's buttons in a menu; with a single button, that button itself.
    @ViewBuilder private var optionsMenu: some View {
        let height = Hovered.optionsSize.height * scale
        let minWidth = Hovered.optionsSize.width * scale
        if content.actions.count == 1, let only = content.actions.first {
            Button { onAction(only) } label: {
                Text(only).font(.system(size: Metrics.fontSize * scale)).foregroundStyle(titleStyle)
                    .lineLimit(1)
                    .padding(.horizontal, 12 * scale)
                    .frame(minWidth: minWidth)
                    .frame(height: height)
                    .background(pillBackground)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            // Use a plain button because SwiftUI Menu restyles and repositions this label.
            Button {
                if let onOptions { onOptions(pillFrame) } else { menuAnchor.popUp(content.actions, onAction) }
            } label: {
                HStack(spacing: 3 * scale) {
                    Text(SystemStrings.options).font(.system(size: Metrics.fontSize * scale))
                    Image(systemName: "chevron.down").font(.system(size: 8 * scale, weight: .bold))
                }
                .foregroundStyle(titleStyle)
                .padding(.horizontal, 10 * scale)
                .frame(minWidth: minWidth)
                .frame(height: height)
                .background(pillBackground)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(MenuAnchorView(anchor: menuAnchor))
        }
    }

    /// Give the pill its own glass to blur the text behind it, then add the highlight.
    private var pillBackground: some View {
        ZStack {
            BannerGlass(shape: Capsule(), cornerRadius: Hovered.optionsSize.height * scale / 2, scale: scale, tint: tint)
            Capsule().fill(Color.primary.opacity(BannerLook.pill))
        }
    }

    /// The card's coordinate space, which the pill's frame is reported in.
    static let space = "bannerCard"

    /// Native hover positions: chevron at top right, Options 10 points from the bottom and right.
    enum Hovered {
        static let chevron = CGRect(x: 319, y: 7, width: 17, height: 19)
        static let optionsSize = CGSize(width: 80, height: 22)
        static let optionsInset: CGFloat = 10
    }

    /// Expanded actions sit below unchanged text, inset 16 points with a divider above each.
    enum Expanded {
        static let collapsedHeight: CGFloat = 58
        static let gapAboveButtons: CGFloat = 5
        static let buttonHeight: CGFloat = 28
        static let divider: CGFloat = 1
        static let sideInset: CGFloat = 16
        static let bottom: CGFloat = 7
        /// Field height plus spacing fills the native 40 point reply area.
        static let replyHeight: CGFloat = 27
        /// More button and chevron positions relative to the top right.
        static let moreFrame = CGRect(x: 299, y: 10, width: 20, height: 13)
        static let chevronFrame = CGRect(x: 318, y: 8, width: 19, height: 17)
        /// Reserve title width for the more button, chevron, and a small gap.
        static let titleClearance: CGFloat = 344 - 14 - moreFrame.minX + 4
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius * scale, style: .continuous)
        return VStack(spacing: 0) {
            summary
            // Keep button height fixed and give the remaining height to multiline text.
            if content.expanded { expandedButtons.fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            BannerGlass(shape: shape, cornerRadius: Metrics.cornerRadius * scale, scale: scale, tint: tint, edge: edge)
        }
        .overlay(alignment: .topLeading) {
            if !content.actions.isEmpty { chrome }
        }
        .contentShape(shape)
        .onTapGesture { onOpen() }
        .coordinateSpace(name: Self.space)
    }

    /// Native expanded actions use centered titles and a divider above each row.
    private var expandedButtons: some View {
        VStack(spacing: 0) {
            ForEach(Array(content.actions.enumerated()), id: \.element) { index, name in
                // With a reply open, its field takes the first button's hairline, and the
                // send button sits right under the field.
                if let reply = content.reply, index == 0 {
                    divider
                    replyField(reply)
                } else {
                    divider
                }
                let sends = content.reply != nil && index == 0
                let waiting = sends && (content.reply ?? "").isEmpty
                Button { onAction(name) } label: {
                    Text(name)
                        .font(.system(size: Metrics.fontSize * scale))
                        .foregroundStyle(waiting ? AnyShapeStyle(.secondary) : titleStyle)
                        .frame(maxWidth: .infinity)
                        .frame(height: Expanded.buttonHeight * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(waiting)
            }
        }
        .padding(.horizontal, Expanded.sideInset * scale)
        .padding(.top, Expanded.gapAboveButtons * scale)
        .padding(.bottom, Expanded.bottom * scale)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(BannerLook.divider)).frame(height: Expanded.divider * scale)
    }

    /// Mirror the native reply field; keystrokes go to the real field.
    private func replyField(_ text: String) -> some View {
        // Use AppKit's accent color because SwiftUI grays it in inactive windows.
        let caret = Rectangle().fill(Color(nsColor: .controlAccentColor)).frame(width: 1 * scale, height: 15 * scale)
        return HStack(spacing: 0) {
            if text.isEmpty { caret }
            Text(text.isEmpty ? content.replyPlaceholder : text)
                .font(.system(size: Metrics.fontSize * scale))
                .foregroundStyle(text.isEmpty ? AnyShapeStyle(.secondary) : bodyStyle)
                .lineLimit(3)
            if !text.isEmpty { caret.padding(.leading, 1) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9 * scale)
        .frame(height: Expanded.replyHeight * scale)
        .background(RoundedRectangle(cornerRadius: 5 * scale, style: .continuous).fill(Color.primary.opacity(BannerLook.field)))
        .overlay(RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
            .strokeBorder(Color.primary.opacity(BannerLook.fieldEdge), lineWidth: scale))
        .padding(.horizontal, -4 * scale)
        .padding(.top, 7 * scale)
        .padding(.bottom, 6 * scale)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: Metrics.iconTextSpacing * scale) {
            iconView
            VStack(alignment: .leading, spacing: Metrics.lineSpacing * scale) {
                // Use the app name only as a fallback for an empty title, matching the native
                // banner.
                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                    Text(content.title.isEmpty ? content.appName : content.title)
                        .font(.system(size: Metrics.fontSize * scale, weight: .semibold))
                        .foregroundStyle(titleStyle)
                        .lineLimit(2)
                        .blur(radius: redactContent ? 6 * scale : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Reserve time width when the hover chevron replaces it so titles do not
                    // reflow.
                    if let time = content.time, !content.expanded {
                        Text(time)
                            .font(.system(size: 11 * scale).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .opacity(hovered || BannerLook.forceHover ? 0 : 1)
                    }
                }
                .padding(.trailing, content.expanded ? Expanded.titleClearance * scale : 0)
                if !content.subtitle.isEmpty {
                    Text(content.subtitle)
                        .font(.system(size: Metrics.fontSize * scale, weight: .semibold))
                        .foregroundStyle(titleStyle)
                        .lineLimit(1)
                        .blur(radius: redactContent ? 6 * scale : 0)
                        .layoutPriority(2)
                }
                if !content.body.isEmpty {
                    Text(content.body)
                        .font(.system(size: Metrics.fontSize * scale))
                        .foregroundStyle(bodyStyle)
                        .lineLimit(edge == .panelRow ? 4 : 3)
                        .blur(radius: redactContent ? 6 * scale : 0)
                        // Prioritize body text; the native panel grants a second title line only
                        // when space remains.
                        .layoutPriority(1)
                }
            }
            // Banners grow to their text; panel rows must fit the native height and truncate body
            // text first.
            .fixedSize(horizontal: false, vertical: edge == .banner)
            // Pad text separately so the icon stays centered in the full card height.
            .padding(.top, Metrics.textTop * scale)
            // Allow two points for taller SwiftUI lines to avoid losing a line within native row
            // heights.
            .padding(.bottom, (edge == .panelRow ? Metrics.textBottom - 2 : Metrics.textBottom) * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Metrics.iconLeading * scale)
        .padding(.trailing, Metrics.textTrailing * scale)
        // Keep text centered above expanded actions with at least the collapsed banner height.
        .frame(maxWidth: .infinity)
        .frame(minHeight: content.expanded ? Expanded.collapsedHeight * scale : nil)
        .frame(maxHeight: .infinity)
    }

    // Use the same native label color for title, subtitle, and body.
    private var titleStyle: AnyShapeStyle {
        textColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary)
    }
    private var bodyStyle: AnyShapeStyle {
        textColor.map { AnyShapeStyle($0.opacity(0.85)) } ?? AnyShapeStyle(.primary)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = content.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: Metrics.iconFrame * scale, height: Metrics.iconFrame * scale)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: Metrics.iconFrame * scale, height: Metrics.iconFrame * scale)
        }
    }
}

/// Banners have a bright rim all around; panel rows have highlights above and below with darker
/// sides.
enum GlassEdge { case banner, panelRow }

struct BannerGlass<S: InsettableShape>: View {
    let shape: S
    /// The glass rounds its own corners; for a pill or a circle, half its height.
    let cornerRadius: CGFloat
    var scale: CGFloat = 1
    var tint: Color = .clear
    var edge: GlassEdge = .banner
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        ZStack {
            BannerBackground(cornerRadius: cornerRadius)
                .opacity(isLight ? BannerLook.lightGlassOpacity : 1)
            // A user tint replaces the brightness wash instead of adding a second layer.
            if tint != .clear {
                tint.opacity(0.45)
            } else if BannerBackground.isGlass {
                Color.white.opacity(isLight ? BannerLook.lightWash : CustomBannerView.Metrics.wash)
                // Additive blending brightens the glass without dimming the backdrop.
                if isLight, BannerLook.lightAdd > 0 {
                    Color.white.opacity(BannerLook.lightAdd).blendMode(.plusLighter)
                }
            }
        }
        .clipShape(shape)
        .overlay {
            if BannerBackground.isGlass, edge == .panelRow {
                panelRowEdge(isLight: isLight)
            } else if BannerBackground.isGlass {
                // Add the native inner rim, which the glass material does not supply.
                shape.strokeBorder(Color.white.opacity(BannerLook.rim), lineWidth: scale)
                if isLight {
                    shape.inset(by: -0.5 * scale).stroke(Color.black.opacity(BannerLook.lightLine), lineWidth: scale)
                }
            } else {
                // Older HUD material needs an explicit hairline.
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
    }
}

extension BannerGlass {
    /// Native panel rim: inner top and bottom highlights, outer dark sides, and faint horizontal
    /// lines on light.
    @ViewBuilder func panelRowEdge(isLight: Bool) -> some View {
        let sides = LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.07),
                                           .init(color: .clear, location: 0.13), .init(color: .clear, location: 0.87),
                                           .init(color: .black, location: 0.93), .init(color: .black, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
        let middle = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.07),
                                            .init(color: .black, location: 0.13), .init(color: .black, location: 0.87),
                                            .init(color: .clear, location: 0.93), .init(color: .clear, location: 1)],
                                    startPoint: .leading, endPoint: .trailing)
        let topAndBottom = LinearGradient(stops: [.init(color: .white.opacity(PanelRowLook.topRim), location: 0),
                                                  .init(color: .white.opacity(PanelRowLook.topRim), location: 0.4),
                                                  .init(color: .white.opacity(PanelRowLook.bottomRim), location: 0.6),
                                                  .init(color: .white.opacity(PanelRowLook.bottomRim), location: 1)],
                                          startPoint: .top, endPoint: .bottom)
        ZStack {
            // The masks reach past the card: the dark lines run just outside it.
            shape.inset(by: -0.5 * scale).stroke(Color.black.opacity(PanelRowLook.sideLine), lineWidth: scale)
                .mask(sides.padding(-2 * scale))
            shape.strokeBorder(topAndBottom, lineWidth: scale)
                .mask(middle)
            if isLight {
                shape.inset(by: -0.5 * scale).stroke(Color.black.opacity(PanelRowLook.lightOuterLine), lineWidth: scale)
                    .mask(middle.padding(-2 * scale))
            }
        }
    }
}

/// The panel row's edge values; a lab build (PROD) takes candidates as NN_LOOK_<NAME>.
enum PanelRowLook {
    private static func value(_ name: String, _ measured: Double) -> Double {
        #if PROD
        if let v = ProcessInfo.processInfo.environment["NN_LOOK_" + name].flatMap(Double.init) { return v }
        #endif
        return measured
    }
    static var sideLine: Double { value("SIDE_LINE", 0.55) }
    static var topRim: Double { value("TOP_RIM", 0.12) }
    static var bottomRim: Double { value("BOTTOM_RIM", 0.25) }
    static var lightOuterLine: Double { value("LIGHT_OUTER_LINE", 0.18) }
}

final class BannerHostingView<Content: View>: NSHostingView<Content> {
    var onRightClick: ((NSPoint) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        guard let onRightClick else { return super.rightMouseDown(with: event) }
        onRightClick(convert(event.locationInWindow, from: nil))
    }
}

/// Reads native banner menus and forwards selections; optionally omits the app actions. See
/// NCMenus.
struct BannerMenuSource {
    let items: (_ withAppActions: Bool, _ done: @escaping ([NCMenuItem]) -> Void) -> Void
    let choose: (NCMenuItem) -> Void
}

/// Anchor app action menus below the Options pill.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
    private var handlers: [() -> Void] = []

    func popUp(_ actions: [String], _ onAction: @escaping (String) -> Void) {
        guard let view else { return }
        let menu = NSMenu()
        handlers = actions.map { name in { onAction(name) } }
        for (i, name) in actions.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 4 : -4), in: view)
    }

    /// Show native menu items, headings, and separators at the anchor or secondary click position.
    func popUp(_ items: [NCMenuItem], at point: NSPoint? = nil, in other: NSView? = nil,
               _ choose: @escaping (NCMenuItem) -> Void) {
        guard let view = other ?? view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        handlers = []
        for item in items {
            switch item.kind {
            case .separator:
                menu.addItem(.separator())
            case .header:
                menu.addItem(.sectionHeader(title: item.title))
            case .action:
                let entry = NSMenuItem(title: item.title, action: #selector(self.choose(_:)), keyEquivalent: "")
                entry.target = self
                entry.tag = handlers.count
                handlers.append { choose(item) }
                menu.addItem(entry)
            }
        }
        let at = point ?? NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 4 : -4)
        menu.popUp(positioning: nil, at: at, in: view)
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard handlers.indices.contains(item.tag) else { return }
        handlers[item.tag]()
    }
}

struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

/// Resolve replica labels from Notification Center's own localization.
enum SystemStrings {
    private static let bundle = Bundle(path: "/System/Library/CoreServices/NotificationCenter.app")
    static let options = bundle?.localizedString(forKey: "Options", value: "Options", table: "Localizable") ?? "Options"
    static let showLess = bundle?.localizedString(forKey: "Show less", value: "Show less", table: "Localizable") ?? "Show less"
}

/// Use Liquid Glass from macOS 26 and HUD material before it.
/// Keep the material behind the content; nesting text inside it would apply vibrancy absent from
/// native banners.
private struct BannerBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    static var isGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            return glass
        }
        #endif
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        // Let the material follow system appearance.
        v.maskImage = Self.maskImage(cornerRadius: cornerRadius)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = v as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            return
        }
        #endif
        (v as? NSVisualEffectView)?.maskImage = Self.maskImage(cornerRadius: cornerRadius)
    }

    private static func maskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius,
                                       bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

@MainActor
final class CustomBannerManager {

    private struct Entry {
        let panel: NSPanel
        let controller: BannerAnimationController
        var dismissTimer: DispatchSourceTimer?
        let onUnderlyingDismiss: (() -> Void)?
        /// Its time is up: the overlay goes, the notification stays.
        let onExpire: (() -> Void)?
        /// Keep the hosting view to redraw content when scale changes.
        let hosting: NSHostingView<CustomBannerView>
        var scale: CGFloat
        /// Where a glide is taking the panel; its frame is still on the way.
        var destination: NSRect?
        /// When that glide ends (system uptime).
        var glideEnds: Double = 0
    }

    private var active: [CFHashCode: Entry] = [:]

    func showBanner(
        content: BannerContent,
        axTopLeft: CGPoint,
        width: CGFloat,
        height: CGFloat,
        scale: Double,
        backgroundColor: Color,
        textColor: Color? = nil,
        redactContent: Bool = false,
        autoDismissSeconds: Double,
        animation: BannerAnimation = .default,
        onOpen: @escaping () -> Void,
        onUnderlyingDismiss: (() -> Void)? = nil,
        onExpire: (() -> Void)? = nil,
        onAction: @escaping (String) -> Void = { _ in },
        onDetails: @escaping () -> Void = {},
        menuSource: BannerMenuSource? = nil,
        key: CFHashCode
    ) {
        dismiss(key: key)

        let controller = BannerAnimationController()
        let onDismissAction: () -> Void = { [weak self] in self?.dismissFromUser(key: key) }
        let onOpenAction:   () -> Void = { [weak self] in onOpen(); self?.dismissFromUser(key: key) }

        let s = CGFloat(scale)
        let frame  = Self.panelFrame(axOrigin: axTopLeft, size: CGSize(width: width, height: height), scale: s)
        let bounds = CGRect(origin: .zero, size: frame.size)

        var bannerView = CustomBannerView(
            content: content, scale: s, animation: animation, tint: backgroundColor,
            textColor: textColor, redactContent: redactContent,
            controller: controller, onDismiss: onDismissAction, onOpen: onOpenAction,
            onAction: onAction, onDetails: onDetails)
        bannerView.menuSource = menuSource
        let hosting = BannerHostingView(rootView: bannerView)
        if let menuSource {
            let anchor = MenuAnchor()
            hosting.onRightClick = { [weak hosting] point in
                guard let hosting else { return }
                menuSource.items(true) { items in anchor.popUp(items, at: point, in: hosting, menuSource.choose) }
            }
        }
        // Use native dimensions; SwiftUI sizing would grow the panel beyond the banner it replaces.
        hosting.sizingOptions = []
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = makePanel(frame: frame, contentView: hosting)
        panel.alphaValue = 1
        panel.orderFront(nil)

        var entry = Entry(panel: panel, controller: controller,
                          onUnderlyingDismiss: onUnderlyingDismiss, onExpire: onExpire,
                          hosting: hosting, scale: s)
        if autoDismissSeconds > 0 {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + autoDismissSeconds)
            timer.setEventHandler { [weak self] in self?.expire(key: key) }
            timer.resume()
            entry.dismissTimer = timer
        }
        active[key] = entry
    }

    private func dismissFromUser(key: CFHashCode) {
        active[key]?.onUnderlyingDismiss?()
        dismiss(key: key)
    }

    /// Expire only the overlay; closing the notification would also remove it from Notification
    /// Center.
    private func expire(key: CFHashCode) {
        active[key]?.onExpire?()
        dismiss(key: key)
    }

    func dismiss(key: CFHashCode) {
        guard let entry = active.removeValue(forKey: key) else { return }
        entry.dismissTimer?.cancel()
        let panel      = entry.panel
        let controller = entry.controller
        controller.dismissCompletion = { [weak panel] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel?.animator().alphaValue = 0
            } completionHandler: {
                panel?.orderOut(nil)
            }
        }
        if let slideOut = controller.slideOutClosure { slideOut() } else { panel.orderOut(nil) }
    }

    func dismissAll() {
        for key in Array(active.keys) { dismiss(key: key) }
    }

    func isActive(key: CFHashCode) -> Bool { active[key] != nil }

    func update(key: CFHashCode, content: BannerContent) {
        guard let entry = active[key], entry.hosting.rootView.content != content else { return }
        entry.hosting.rootView.content = content
    }

    /// Suspend expiry while interacting; the native banner still controls when it disappears.
    func holdOpen(key: CFHashCode) {
        active[key]?.dismissTimer?.cancel()
        active[key]?.dismissTimer = nil
    }
    /// When the overlay's glide ends (system uptime); in the past when it isn't gliding.
    func glideEnd(key: CFHashCode) -> Double { active[key]?.glideEnds ?? 0 }
    /// Where the overlay's panel is right now, partway through a glide included.
    func frame(key: CFHashCode) -> NSRect? { active[key]?.panel.frame }
    var hasActive: Bool { !active.isEmpty }

    func resetDismissTimers(autoDismissSeconds: Double) {
        for key in Array(active.keys) {
            active[key]?.dismissTimer?.cancel()
            active[key]?.dismissTimer = nil
            guard autoDismissSeconds > 0 else { continue }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + autoDismissSeconds)
            timer.setEventHandler { [weak self] in self?.expire(key: key) }
            timer.resume()
            active[key]?.dismissTimer = timer
        }
    }

    /// With `glide`, ease into a changed pile position. Settings drags must follow the pointer
    /// immediately.
    func move(key: CFHashCode, axTopLeft: CGPoint, width: CGFloat, height: CGFloat, scale: CGFloat? = nil,
              glide: Bool = false) {
        guard var entry = active[key] else { return }

        // Redraw both dimensions at the new scale so existing content is not stretched.
        if let scale, abs(scale - entry.scale) > 0.001 {
            entry.hosting.rootView.scale = scale
            entry.scale = scale
            active[key] = entry
        }

        let target = Self.panelFrame(axOrigin: axTopLeft, size: CGSize(width: width, height: height),
                                     scale: entry.scale)
        // Compare the destination during glides so sweeps do not restart the animation.
        let current = entry.destination ?? entry.panel.frame
        guard current != target else { return }

        if glide {
            // Ignore tiny settling changes that would otherwise shimmer.
            guard hypot(target.minX - current.minX, target.minY - current.minY) >= 2
                    || abs(target.width - current.width) >= 2 || abs(target.height - current.height) >= 2
            else { return }
            entry.destination = target
            active[key] = entry
            let panel = entry.panel
            // Farther takes a little longer, so two slots don't move at twice the
            // speed of one.
            let distance = hypot(target.minX - current.minX, target.minY - current.minY)
            let duration = min(Self.maxGlideDuration, max(Self.glideDuration, distance / 400))
            active[key]?.glideEnds = ProcessInfo.processInfo.systemUptime + duration
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: false)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    if self?.active[key]?.destination == target { self?.active[key]?.destination = nil }
                }
            }
            return
        }
        entry.destination = nil
        active[key] = entry

        // Move without resizing when size is unchanged to avoid a synchronous SwiftUI redraw on
        // every drag frame.
        if current.size == target.size {
            entry.panel.setFrameOrigin(target.origin)
        } else {
            entry.panel.setFrame(target, display: true, animate: false)
            entry.hosting.frame = CGRect(origin: .zero, size: target.size)
        }
    }

    /// Duration for one slot of motion; longer distances are capped by maxGlideDuration.
    static let glideDuration: Double = 0.22
    static let maxGlideDuration: Double = 0.4

    private func makePanel(frame: NSRect, contentView: NSView) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Glass window shadows form a dark ring absent from the native banner.
        panel.hasShadow = !BannerBackground.isGlass
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = contentView
        return panel
    }

    /// Include transparent chrome margins for the overhanging close button; clear pixels pass
    /// clicks through.
    static func panelFrame(axOrigin: CGPoint, size: CGSize, scale: CGFloat) -> NSRect {
        let inset = CustomBannerView.Metrics.chromeInset * scale
        return axRect(axOrigin: axOrigin, size: size).insetBy(dx: -inset, dy: -inset)
    }

    static func axRect(axOrigin: CGPoint, size: CGSize) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsY = primaryHeight - axOrigin.y - size.height
        return NSRect(x: axOrigin.x, y: nsY, width: size.width, height: size.height)
    }
}
