import AppKit
import SwiftUI

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

    static func == (l: BannerContent, r: BannerContent) -> Bool {
        l.appName == r.appName && l.title == r.title && l.subtitle == r.subtitle && l.body == r.body
    }
}

@MainActor
final class BannerAnimationController {
    var slideOutClosure: (() -> Void)?
    var dismissCompletion: (() -> Void)?
}

struct CustomBannerView: View {
    let content: BannerContent
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

    @State private var animX: CGFloat
    @State private var animY: CGFloat
    @State private var animOpacity: Double
    @State private var animScale: CGFloat
    @State private var animRotation: Double
    @State private var isHovered = false
    @State private var animationsSetup = false
    @State private var cursorPushed = false

    init(content: BannerContent, scale: CGFloat, animation: BannerAnimation, tint: Color,
         textColor: Color?, redactContent: Bool = false, controller: BannerAnimationController,
         onDismiss: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.content = content
        self.scale = scale
        self.animation = animation
        self.tint = tint
        self.textColor = textColor
        self.redactContent = redactContent
        self.controller = controller
        self.onDismiss = onDismiss
        self.onOpen = onOpen
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
        static let closeCentre: CGFloat = 5
        static let chromeInset: CGFloat = 8
    }

    var body: some View {
        let inset = Metrics.chromeInset * scale
        banner
            .overlay(alignment: .topLeading) {
                if isHovered {
                    closeButton
                        .offset(x: (Metrics.closeCentre - Metrics.closeDiameter / 2) * scale,
                                y: (Metrics.closeCentre - Metrics.closeDiameter / 2) * scale)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(inset)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
                setCursorPushed(hovering)
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
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius * scale, style: .continuous)
        return HStack(alignment: .center, spacing: Metrics.iconTextSpacing * scale) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                BannerBackground(cornerRadius: Metrics.cornerRadius * scale)
                // Untinted means "look like the system banner". The glass alone
                // comes out slightly dark, so it gets the measured wash; a user
                // tint replaces the wash rather than stacking on top of it.
                if tint != .clear {
                    tint.opacity(0.45)
                } else if BannerBackground.isGlass {
                    Color.white.opacity(Metrics.wash)
                }
            }
            .clipShape(shape)
        }
        .overlay {
            // Glass draws its own edge. The pre-26 material needs the hairline.
            if !BannerBackground.isGlass {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
        .contentShape(shape)
        .onTapGesture { onOpen() }
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

    // The system banner draws title, subtitle and body all in the label colour,
    // which is 85% white in Dark Mode and 85% black in Light Mode.
    private var titleStyle: AnyShapeStyle {
        textColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary)
    }
    private var bodyStyle: AnyShapeStyle {
        textColor.map { AnyShapeStyle($0.opacity(0.85)) } ?? AnyShapeStyle(.primary)
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

    @ViewBuilder
    private var iconView: some View {
        if let icon = content.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: Metrics.iconFrame * scale, height: Metrics.iconFrame * scale)
        } else {
            // Sized to the visible squircle of a real app icon, not to its frame.
            ZStack {
                Color.primary.opacity(0.12)
                Image(systemName: "bell.fill")
                    .foregroundStyle(.primary.opacity(0.7))
                    .font(.system(size: 15 * scale, weight: .medium))
            }
            .frame(width: 31 * scale, height: 31 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous))
            .frame(width: Metrics.iconFrame * scale, height: Metrics.iconFrame * scale)
        }
    }
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
            controller: controller, onDismiss: onDismissAction, onOpen: onOpenAction)
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

    func move(key: CFHashCode, axTopLeft: CGPoint, width: CGFloat, height: CGFloat, scale: CGFloat? = nil) {
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
        let current = entry.panel.frame
        guard current != target else { return }

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
