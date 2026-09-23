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
    let body: String
    let appIcon: NSImage?

    static func == (l: BannerContent, r: BannerContent) -> Bool {
        l.appName == r.appName && l.title == r.title && l.body == r.body
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

    var body: some View {
        HStack(spacing: 10 * scale) {
            iconView
            VStack(alignment: .leading, spacing: 2 * scale) {
                HStack(alignment: .firstTextBaseline) {
                    Text(content.appName.uppercased())
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(appNameStyle)
                        .kerning(0.4)
                        .lineLimit(1)
                    Spacer()
                    LocalizedText("now")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(timestampStyle)
                }
                if !content.title.isEmpty {
                    Text(content.title)
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundStyle(titleStyle)
                        .lineLimit(1)
                        .blur(radius: redactContent ? 6 * scale : 0)
                }
                if !content.body.isEmpty {
                    Text(content.body)
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(bodyStyle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .blur(radius: redactContent ? 6 * scale : 0)
                }
            }
        }
        .padding(EdgeInsets(top: 4 * scale, leading: 8 * scale,
                            bottom: 4 * scale, trailing: 8 * scale))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                VisualEffectBackground(cornerRadius: 14 * scale)
                // Untinted means "look like the system banner", so nothing is
                // painted over the material at all. A flat black wash used to sit
                // here, which is why an untinted custom banner could never be made
                // to match Notification Center: no tint setting could cancel it.
                if tint != .clear {
                    tint.opacity(0.45)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 20 * scale, height: 20 * scale)
                        Image(systemName: "xmark")
                            .font(.system(size: 9 * scale, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .padding(8 * scale)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
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

    private var appNameStyle: AnyShapeStyle {
        textColor.map { AnyShapeStyle($0.opacity(0.65)) } ?? AnyShapeStyle(.secondary)
    }
    private var timestampStyle: AnyShapeStyle {
        textColor.map { AnyShapeStyle($0.opacity(0.55)) } ?? AnyShapeStyle(.tertiary)
    }
    private var titleStyle: AnyShapeStyle {
        textColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary)
    }
    private var bodyStyle: AnyShapeStyle {
        textColor.map { AnyShapeStyle($0.opacity(0.85)) } ?? AnyShapeStyle(Color.primary.opacity(0.85))
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
        Group {
            if let icon = content.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                ZStack {
                    Color.primary.opacity(0.12)
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.primary.opacity(0.7))
                        .font(.system(size: 17 * scale, weight: .medium))
                }
            }
        }
        .frame(width: 36 * scale, height: 36 * scale)
        .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        // Deliberately no forced appearance. Leaving this nil lets the material
        // follow the system's light/dark setting, which is what the real banner
        // does. Forcing .darkAqua was reintroduced in 14c4c49 to make untinted
        // banners "match native", but it only matches in Dark Mode: in Light Mode
        // it swapped a light system banner for a dark custom one. 1c79558 had
        // already removed it once for the same reason.
        v.maskImage = Self.maskImage(cornerRadius: cornerRadius)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.maskImage = Self.maskImage(cornerRadius: cornerRadius)
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
        let bannerHeight = Self.bannerHeight(forScale: s)
        let frame  = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: bannerHeight))
        let bounds = CGRect(origin: .zero, size: frame.size)

        let bannerView = CustomBannerView(
            content: content, scale: s, animation: animation, tint: backgroundColor,
            textColor: textColor, redactContent: redactContent,
            controller: controller, onDismiss: onDismissAction, onOpen: onOpenAction)
        let hosting = NSHostingView(rootView: bannerView)
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

    func move(key: CFHashCode, axTopLeft: CGPoint, width: CGFloat, scale: CGFloat? = nil) {
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

        let height = Self.bannerHeight(forScale: entry.scale)
        let target = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: height))
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

    static func bannerHeight(forScale scale: CGFloat) -> CGFloat { 62 * scale }

    private func makePanel(frame: NSRect, contentView: NSView) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = contentView
        return panel
    }

    static func axRect(axOrigin: CGPoint, size: CGSize) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsY = primaryHeight - axOrigin.y - size.height
        return NSRect(x: axOrigin.x, y: nsY, width: size.width, height: size.height)
    }
}
