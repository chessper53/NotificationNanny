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

    /// Everything one animation case needs to drive its intro/outro — bundled so
    /// adding a new `BannerAnimation` case means writing one `Spec`, not editing
    /// four separate switches that have to be kept in sync by hand.
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

    static func == (l: BannerContent, r: BannerContent) -> Bool {
        l.appName == r.appName && l.title == r.title && l.subtitle == r.subtitle && l.body == r.body
            && l.actions == r.actions && l.expanded == r.expanded && l.reply == r.reply
    }
}

/// How the replica differs between appearances, measured against the system banner with
/// scripts/banner-lab. A lab build (compiled with PROD) takes candidates from the
/// environment, NN_LOOK_<NAME>, to try them without editing this.
enum BannerLook {
    private static func value(_ name: String, _ measured: Double) -> Double {
        #if PROD
        if let v = ProcessInfo.processInfo.environment["NN_LOOK_" + name].flatMap(Double.init) { return v }
        #endif
        return measured
    }
    /// The white wash over the glass in Light Mode; Dark Mode's is Metrics.wash. None:
    /// it dims what shows through, and Light Mode needs the opposite.
    static var lightWash: Double { value("LIGHT_WASH", 0) }
    /// The glass is a little too dense in Light Mode: the system banner lets more of what
    /// is behind it through (0.475 of it against our 0.43, measured on white, black and
    /// gray), and brightens by a constant on top, see lightAdd.
    static var lightGlassOpacity: Double { value("LIGHT_GLASS", 0.92) }
    /// White added on top in Light Mode (plus-lighter), brightening without dimming.
    /// Inside the banner within 1.5 levels of the system's on every backdrop measured,
    /// against 12 before (on white).
    static var lightAdd: Double { value("LIGHT_ADD", 0.037) }
    /// The bright line just inside the edge, both appearances.
    /// 0.25 in both: the edge 2.4 levels off in Dark Mode and 2.1 in Light, against 6.3.
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
    /// Mutable so a scale change while the banner is on screen re-renders it at
    /// the new size rather than stretching what is already drawn.
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

    /// Geometry of the system banner, measured in points from a real macOS 27
    /// banner with scripts/banner-lab rather than eyeballed. Everything is
    /// multiplied by `scale` at the point of use.
    enum Metrics {
        static let cornerRadius: CGFloat = 20
        /// Frame the app icon is drawn into. App icons carry the standard grid
        /// padding, so the visible squircle is about 31pt, which is what the
        /// system banner shows.
        static let iconFrame: CGFloat = 38
        static let iconLeading: CGFloat = 10
        /// Text starts 58pt from the leading edge: 10 + 38 + 10.
        static let iconTextSpacing: CGFloat = 10
        static let textTop: CGFloat = 12
        static let textBottom: CGFloat = 13
        static let textTrailing: CGFloat = 14
        static let lineSpacing: CGFloat = 1
        static let fontSize: CGFloat = 13
        /// A faint white wash over the glass. Without it the replica sits a few
        /// levels darker than the system banner on every backdrop measured, in
        /// both Light and Dark Mode.
        static let wash: Double = 0.05
        /// The close button is centred just inside the corner and overhangs it,
        /// so the panel is grown by this much on every side to leave it room.
        static let closeDiameter: CGFloat = 20
        /// The close button's top left, from the banner's: it overhangs the corner.
        /// Measured from a hovered system banner (scripts/banner-lab `real-states`).
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
                   onOpen: onOpen, onAction: onAction, onDetails: onDetails)
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

/// The banner itself, as the system draws it: glass, icon, text, and when its details are
/// shown, the app's buttons. Shared by the custom banner and the custom Notification
/// Center, whose rows are banners too (measured on 27.0, scripts/panel-lab
/// `panel-shots`), so both look the same and take the same tint and text colour.
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

    @Environment(\.colorScheme) private var colorScheme
    private var isLight: Bool { colorScheme == .light }
    @State private var menuAnchor: MenuAnchor = MenuAnchor()

    typealias Metrics = CustomBannerView.Metrics

    /// What the system banner adds for the app's buttons, at the places measured on a real
    /// one: hovered, a chevron that shows the details and an Options menu of the buttons;
    /// with the details shown, a more menu and the chevron turned down.
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
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: Expanded.moreFrame.width * scale, height: Expanded.moreFrame.height * scale)
                        .offset(x: Expanded.moreFrame.minX * scale, y: Expanded.moreFrame.minY * scale)
                } else {
                    optionsMenu
                        .offset(x: Hovered.options.minX * scale, y: Hovered.options.minY * scale)
                }
            }
            .transition(.opacity)
        }
    }

    private var chevron: CGRect { content.expanded ? Expanded.chevronFrame : Hovered.chevron }

    /// Options and the app's buttons in a menu; with a single button, that button itself.
    @ViewBuilder private var optionsMenu: some View {
        let pill = Capsule().fill(Color.primary.opacity(BannerLook.pill))
        let size = CGSize(width: Hovered.options.width * scale, height: Hovered.options.height * scale)
        if content.actions.count == 1, let only = content.actions.first {
            Button { onAction(only) } label: {
                Text(only).font(.system(size: Metrics.fontSize * scale)).foregroundStyle(titleStyle)
                    .frame(width: size.width, height: size.height).background(pill)
            }
            .buttonStyle(.plain)
        } else {
            // A plain button opening the menu itself: SwiftUI's Menu restyles its label,
            // moving the arrow in front and dropping the pill.
            Button { menuAnchor.popUp(content.actions, onAction) } label: {
                HStack(spacing: 3 * scale) {
                    Text(SystemStrings.options).font(.system(size: Metrics.fontSize * scale))
                    Image(systemName: "chevron.down").font(.system(size: 8 * scale, weight: .bold))
                }
                .foregroundStyle(titleStyle)
                .frame(width: size.width, height: size.height)
                .background(pill)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(MenuAnchorView(anchor: menuAnchor))
        }
    }

    /// Hovered, from a real banner's frames.
    enum Hovered {
        static let chevron = CGRect(x: 319, y: 7, width: 17, height: 19)
        static let options = CGRect(x: 254, y: 26, width: 80, height: 22)
    }

    /// The system banner with its details shown, from a real one's frames: the text where
    /// it is collapsed, then one row per button under a hairline, 16 points in from each
    /// side, and a little room under the last.
    enum Expanded {
        static let collapsedHeight: CGFloat = 58
        static let gapAboveButtons: CGFloat = 5
        static let buttonHeight: CGFloat = 28
        static let divider: CGFloat = 1
        static let sideInset: CGFloat = 16
        static let bottom: CGFloat = 7
        /// The reply field's box; with its spacing it fills the 40 points between the
        /// hairline and the send button on the real one.
        static let replyHeight: CGFloat = 27
        /// The more menu (⋯) and the chevron, from the top right corner.
        static let moreFrame = CGRect(x: 299, y: 10, width: 20, height: 13)
        static let chevronFrame = CGRect(x: 318, y: 8, width: 19, height: 17)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius * scale, style: .continuous)
        return VStack(spacing: 0) {
            summary
            if content.expanded { expandedButtons }
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
    }

    /// The app's buttons and an open reply, as the system banner shows them with its
    /// details: plain centred titles in full-width rows, a hairline above each.
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

    /// The system's reply field: a rounded box a little lighter than the banner, with the
    /// app's placeholder and the caret. The typing itself goes to the real one.
    private func replyField(_ text: String) -> some View {
        // The caret is the system accent: Color.accentColor turns gray in a window of an
        // app that isn't active, which this always is. It stands before the placeholder,
        // and after what is typed.
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
        // Text and caret 9 points into the box, as on the real one (21 from the banner's edge).
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
                // The system banner shows the app name in the title slot when a
                // notification has no title, and never shows it anywhere else.
                Text(content.title.isEmpty ? content.appName : content.title)
                    .font(.system(size: Metrics.fontSize * scale, weight: .semibold))
                    .foregroundStyle(titleStyle)
                    .lineLimit(2)
                    .blur(radius: redactContent ? 6 * scale : 0)
                if !content.subtitle.isEmpty {
                    Text(content.subtitle)
                        .font(.system(size: Metrics.fontSize * scale, weight: .semibold))
                        .foregroundStyle(titleStyle)
                        .lineLimit(1)
                        .blur(radius: redactContent ? 6 * scale : 0)
                }
                if !content.body.isEmpty {
                    Text(content.body)
                        .font(.system(size: Metrics.fontSize * scale))
                        .foregroundStyle(bodyStyle)
                        .lineLimit(3)
                        .blur(radius: redactContent ? 6 * scale : 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // Vertical padding belongs to the text alone. The icon frame is taller
            // than a one line banner leaves room for between the paddings, and it
            // is centred in the full height on the system banner anyway.
            .padding(.top, Metrics.textTop * scale)
            .padding(.bottom, Metrics.textBottom * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Metrics.iconLeading * scale)
        .padding(.trailing, Metrics.textTrailing * scale)
        // Collapsed it fills the banner and stays centred, as before; expanded it keeps
        // the collapsed height, so the text doesn't move, with the buttons under it.
        .frame(maxWidth: .infinity)
        .frame(height: content.expanded ? Expanded.collapsedHeight * scale : nil)
        .frame(maxHeight: content.expanded ? nil : .infinity)
    }

    // The system banner draws title, subtitle and body all in the label colour,
    // which is 85% white in Dark Mode and 85% black in Light Mode.
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
            // Without an icon of its own, the generic app icon, as the system banner shows.
            Image(nsImage: NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: Metrics.iconFrame * scale, height: Metrics.iconFrame * scale)
        }
    }
}

/// The system banner's glass, as measured against a real one in both appearances (see
/// BannerLook), for any shape: the banner itself, and the glass buttons and stack edges
/// of the custom Notification Center, which the system draws the same way.
/// How the glass catches the light along its edge. A banner's shines all the way round; a
/// row of the Notification Center panel is lit from above and below, with a dark line
/// along its sides instead (both measured, scripts/banner-lab and panel-lab compare.sh).
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
            // Untinted means "look like the system banner". The glass alone comes out
            // slightly dark, so it gets the measured wash; a user tint replaces the wash
            // rather than stacking on top of it.
            if tint != .clear {
                tint.opacity(0.45)
            } else if BannerBackground.isGlass {
                Color.white.opacity(isLight ? BannerLook.lightWash : CustomBannerView.Metrics.wash)
                // Light Mode's glass is brighter by a constant on any backdrop, which a
                // wash can't give: a wash also dims what shows through.
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
                // The system banner's glass catches the light along its edge, one point
                // inside it, in both appearances; ours doesn't by itself.
                shape.strokeBorder(Color.white.opacity(BannerLook.rim), lineWidth: scale)
                // In Light Mode a fine dark line runs just outside it as well.
                if isLight {
                    shape.inset(by: -0.5 * scale).stroke(Color.black.opacity(BannerLook.lightLine), lineWidth: scale)
                }
            } else {
                // The pre-26 material needs the hairline.
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
    }
}

extension BannerGlass {
    /// A panel row's edge: bright just inside its top and bottom, a dark line just outside
    /// its sides and round its corners, and in Light Mode a fainter one above and below.
    /// Measured against the real panel over a gray backdrop: the side line comes out at
    /// 46 where the backdrop is 101, the highlights 17 above the inside at the top and 30
    /// at the bottom.
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

/// Where a menu of the app's buttons opens: under the Options pill, as the system's does.
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

/// Notification Center's own words for what the replica draws, so they read as the
/// system's do, in the language Notification Center shows.
enum SystemStrings {
    private static let bundle = Bundle(path: "/System/Library/CoreServices/NotificationCenter.app")
    static let options = bundle?.localizedString(forKey: "Options", value: "Options", table: "Localizable") ?? "Options"
    static let showLess = bundle?.localizedString(forKey: "Show less", value: "Show less", table: "Localizable") ?? "Show less"
}

/// Liquid Glass on macOS 26 and later, which is what the system banner is made
/// of; the old HUD material before that. Glass goes in a sibling view underneath
/// the SwiftUI content, never as its container, because content inside a glass
/// view gets vibrant blending and the system banner's text does not.
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
        // No forced appearance: the material follows the system's light/dark
        // setting, as the real banner does. 1c79558 and bfbd39e both removed a
        // forced .darkAqua that only matched in Dark Mode.
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
        /// Kept so a live scale change can re-render the SwiftUI content instead
        /// of stretching the already-rendered view.
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
        onAction: @escaping (String) -> Void = { _ in },
        onDetails: @escaping () -> Void = {},
        key: CFHashCode
    ) {
        dismiss(key: key)

        let controller = BannerAnimationController()
        let onDismissAction: () -> Void = { [weak self] in self?.dismissFromUser(key: key) }
        let onOpenAction:   () -> Void = { [weak self] in onOpen(); self?.dismissFromUser(key: key) }

        let s = CGFloat(scale)
        let frame  = Self.panelFrame(axOrigin: axTopLeft, size: CGSize(width: width, height: height), scale: s)
        let bounds = CGRect(origin: .zero, size: frame.size)

        let bannerView = CustomBannerView(
            content: content, scale: s, animation: animation, tint: backgroundColor,
            textColor: textColor, redactContent: redactContent,
            controller: controller, onDismiss: onDismissAction, onOpen: onOpenAction,
            onAction: onAction, onDetails: onDetails)
        let hosting = NSHostingView(rootView: bannerView)
        // The panel's size comes from the real banner, never from SwiftUI. Left
        // to its default, the hosting view grows the panel to its own minimum
        // size, which pushes the banner off the spot it is meant to cover.
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
                          onUnderlyingDismiss: onUnderlyingDismiss,
                          hosting: hosting, scale: s)
        if autoDismissSeconds > 0 {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + autoDismissSeconds)
            timer.setEventHandler { [weak self] in self?.dismissFromUser(key: key) }
            timer.resume()
            entry.dismissTimer = timer
        }
        active[key] = entry
    }

    private func dismissFromUser(key: CFHashCode) {
        active[key]?.onUnderlyingDismiss?()
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

    /// Shows the real banner's state again: its buttons opened, a reply typed.
    func update(key: CFHashCode, content: BannerContent) {
        guard let entry = active[key], entry.hosting.rootView.content != content else { return }
        entry.hosting.rootView.content = content
    }

    /// Someone is using the banner's buttons or replying: it stays until they are done,
    /// whatever auto-dismiss says. The real banner still decides when it goes.
    func holdOpen(key: CFHashCode) {
        active[key]?.dismissTimer?.cancel()
        active[key]?.dismissTimer = nil
    }
    /// When the overlay's glide ends (system uptime); in the past when it isn't gliding.
    func glideEnd(key: CFHashCode) -> Double { active[key]?.glideEnds ?? 0 }
    var hasActive: Bool { !active.isEmpty }

    func resetDismissTimers(autoDismissSeconds: Double) {
        for key in Array(active.keys) {
            active[key]?.dismissTimer?.cancel()
            active[key]?.dismissTimer = nil
            guard autoDismissSeconds > 0 else { continue }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + autoDismissSeconds)
            timer.setEventHandler { [weak self] in self?.dismiss(key: key) }
            timer.resume()
            active[key]?.dismissTimer = timer
        }
    }

    /// - Parameter glide: ease into place instead of jumping, for a pile closing
    ///   a gap or making room. A settings drag must not glide: it would trail
    ///   behind the pointer.
    func move(key: CFHashCode, axTopLeft: CGPoint, width: CGFloat, height: CGFloat, scale: CGFloat? = nil,
              glide: Bool = false) {
        guard var entry = active[key] else { return }

        // A live scale change has to re-render the SwiftUI content at the new
        // scale. Previously only the panel's width was touched while its height
        // stayed at whatever it was when the banner appeared, and the hosting
        // view autoresized — so the already-rendered banner was stretched into
        // the new frame instead of laid out again, which is the "squish".
        if let scale, abs(scale - entry.scale) > 0.001 {
            entry.hosting.rootView.scale = scale
            entry.scale = scale
            active[key] = entry
        }

        let target = Self.panelFrame(axOrigin: axTopLeft, size: CGSize(width: width, height: height),
                                     scale: entry.scale)
        // Compared with where it is heading, so a sweep during a glide doesn't
        // restart it.
        let current = entry.destination ?? entry.panel.frame
        guard current != target else { return }

        if glide {
            // A point or two is the banner settling, not the pile moving; easing
            // that only made it shimmer.
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
                // A size change of a point or two rides along; the hosting view
                // follows the panel through its autoresizing mask.
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

        // Dragging the position tile drives this at screen refresh rate. When only
        // the origin moves, which is the common case, setFrameOrigin skips the
        // resize and redraw path; setFrame(display: true) was forcing a
        // synchronous re-render of the blurred, SwiftUI-hosted content every frame.
        if current.size == target.size {
            entry.panel.setFrameOrigin(target.origin)
        } else {
            entry.panel.setFrame(target, display: true, animate: false)
            entry.hosting.frame = CGRect(origin: .zero, size: target.size)
        }
    }

    /// How long a pile takes to close a gap or make room, close to macOS's own
    /// slide: one slot in this, farther up to `maxGlideDuration`.
    static let glideDuration: Double = 0.22
    static let maxGlideDuration: Double = 0.4

    private func makePanel(frame: NSRect, contentView: NSView) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system banner casts next to no shadow. A window shadow here is
        // traced from the glass's alpha and comes out as a hard dark ring.
        panel.hasShadow = !BannerBackground.isGlass
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = contentView
        return panel
    }

    /// The panel covers the banner plus `chromeInset` on every side, so the
    /// close button can overhang the corner the way the system one does. The
    /// margin is transparent, and transparent parts of a window let clicks through.
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
