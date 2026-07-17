import AppKit
import SwiftUI

// MARK: - Animation

package enum BannerAnimation: String, Codable, CaseIterable {
    case `default`  = "Default"
    case fade       = "Fade"
    case scale      = "Scale"
    case bounce     = "Bounce"
    case drop       = "Drop"
    case slideLeft  = "SlideLeft"
    case rise       = "Rise"
    case swing      = "Swing"

    /// User-facing name (rawValue is persisted, so keep it stable; relabel here).
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

    /// A banner's resting state is always the identity transform; each animation only
    /// differs in where it starts/ends (the `hidden` transform) and the curve used.
    /// Driving every case from this one table keeps the resting frame aligned for all
    /// of them — the earlier per-case code forgot to reset the slide offset, which is
    /// what shifted non-default banners sideways.
    struct Transform: Equatable {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var opacity: Double = 1
        var scale: CGFloat = 1
        var rotation: Double = 0   // degrees
    }

    var hidden: Transform {
        switch self {
        case .default:   return Transform(x: 150)
        case .fade:      return Transform(opacity: 0)
        case .scale:     return Transform(opacity: 0, scale: 0.8)
        case .bounce:    return Transform(opacity: 0, scale: 0.5)
        case .drop:      return Transform(y: -120)
        case .slideLeft: return Transform(x: -150)
        case .rise:      return Transform(y: 120, opacity: 0)
        case .swing:     return Transform(opacity: 0, scale: 0.9, rotation: -8)
        }
    }

    var intro: Animation {
        switch self {
        case .default:   return .spring(response: 0.45, dampingFraction: 0.78)
        case .fade:      return .easeOut(duration: 0.35)
        case .scale:     return .spring(response: 0.40, dampingFraction: 0.72)
        case .bounce:    return .spring(response: 0.50, dampingFraction: 0.55)
        case .drop:      return .spring(response: 0.50, dampingFraction: 0.70)
        case .slideLeft: return .spring(response: 0.45, dampingFraction: 0.80)
        case .rise:      return .spring(response: 0.48, dampingFraction: 0.78)
        case .swing:     return .spring(response: 0.50, dampingFraction: 0.52)
        }
    }

    var outro: Animation {
        switch self {
        case .default:        return .spring(response: 0.35, dampingFraction: 0.85)
        case .scale, .bounce: return .easeIn(duration: 0.20)
        default:              return .easeIn(duration: 0.22)
        }
    }

    var outroDuration: Double { self == .default ? 0.38 : 0.24 }
}

// MARK: - Data

struct BannerContent: Equatable {
    let appName: String
    let title: String
    let body: String
    let appIcon: NSImage?

    /// Identity is the text only — the icon is derived from the app name, so it never differs
    /// when the text matches. Used to detect when NC reuses a window for a newer message.
    static func == (l: BannerContent, r: BannerContent) -> Bool {
        l.appName == r.appName && l.title == r.title && l.body == r.body
    }
}

// MARK: - Animation Controller

@MainActor
final class BannerAnimationController {
    var slideOutClosure: (() -> Void)?
    var dismissCompletion: (() -> Void)?
}

// MARK: - View

struct CustomBannerView: View {
    let content: BannerContent
    let scale: CGFloat
    let animation: BannerAnimation
    let tint: Color
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
         controller: BannerAnimationController,
         onDismiss: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.content = content
        self.scale = scale
        self.animation = animation
        self.tint = tint
        self.controller = controller
        self.onDismiss = onDismiss
        self.onOpen = onOpen
        // Start in the hidden pose so the first painted frame is already off-screen /
        // transparent — the box then animates to rest in onAppear. No panel alpha fade
        // is needed to mask a flash, which lets translate-in animations show immediately.
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
                        .foregroundStyle(.secondary)
                        .kerning(0.4)
                        .lineLimit(1)
                    Spacer()
                    Text("now")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.tertiary)
                }
                if !content.title.isEmpty {
                    Text(content.title)
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if !content.body.isEmpty {
                    Text(content.body)
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(EdgeInsets(top: 4 * scale, leading: 8 * scale,
                            bottom: 4 * scale, trailing: 8 * scale))
        // Fill the whole panel so the chrome below *is* the box — when the transforms at
        // the end of the chain run, the entire box animates together (matching the
        // preview), rather than just the content sliding inside a static box.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                VisualEffectBackground(cornerRadius: 14 * scale)
                Color.black.opacity(0.28)
                if tint != .clear { tint.opacity(0.45) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 20 * scale, height: 20 * scale)
                        Image(systemName: "xmark")
                            .font(.system(size: 9 * scale, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
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

    private func setupAnimations() {
        // State already starts in the hidden pose (set in init), so just animate to rest.
        let hidden = animation.hidden
        controller.slideOutClosure = {
            withAnimation(animation.outro) { apply(hidden) }
            scheduleDismiss(after: animation.outroDuration)
        }
        withAnimation(animation.intro) { apply(.init()) }   // .init() == resting/aligned
    }

    /// Push/pop a pointing-hand cursor so the banner reads as clickable. Guarded by
    /// `cursorPushed` to keep the global cursor stack balanced — `onDisappear` covers the
    /// case where the panel is dismissed (auto-dismiss / click) while still hovered, since
    /// `onHover(false)` may not fire when the hosting view is torn down.
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
                    Color.white.opacity(0.12)
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.system(size: 17 * scale, weight: .medium))
                }
            }
        }
        .frame(width: 36 * scale, height: 36 * scale)
        .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
    }
}

// MARK: - Blur background

/// A `.behindWindow` vibrancy view exposed to SwiftUI so it can live *inside* the
/// animated banner box (and thus translate/scale/fade with it). SwiftUI's `.clipShape`
/// doesn't reliably round an AppKit vibrancy layer, so corners are rounded here via the
/// view's own `maskImage` — a stretchable rounded-rect image.
private struct VisualEffectBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
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

// MARK: - Manager

@MainActor
final class CustomBannerManager {

    private struct Entry {
        let panel: NSPanel
        let controller: BannerAnimationController
        var dismissTimer: DispatchSourceTimer?
        /// Retires the real NC banner hidden behind this overlay. Run only when the overlay
        /// dismisses itself (user close, tap-to-open, auto-dismiss timer) — not when the
        /// repositioner tears it down to swap in a native banner. nil for overlays with no
        /// backing NC window to retire.
        let onUnderlyingDismiss: (() -> Void)?
    }

    private var active: [CFHashCode: Entry] = [:]

    func showBanner(
        content: BannerContent,
        axTopLeft: CGPoint,
        width: CGFloat,
        scale: Double,
        backgroundColor: Color,
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
        let bannerHeight: CGFloat = 62 * s
        let frame  = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: bannerHeight))
        let bounds = CGRect(origin: .zero, size: frame.size)

        // The box chrome (blur, tint, rounded corners) now lives inside the SwiftUI view
        // so it animates as one unit with the content. The hosting view fills the panel
        // with a transparent background; the panel's drop shadow follows the rounded box.
        let bannerView = CustomBannerView(
            content: content, scale: s, animation: animation, tint: backgroundColor,
            controller: controller, onDismiss: onDismissAction, onOpen: onOpenAction)
        let hosting = NSHostingView(rootView: bannerView)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        // No alpha fade-in: the box starts in its hidden pose and animates to rest itself.
        let panel = makePanel(frame: frame, contentView: hosting)
        panel.alphaValue = 1
        panel.orderFront(nil)

        var entry = Entry(panel: panel, controller: controller, onUnderlyingDismiss: onUnderlyingDismiss)
        let timeout = autoDismissSeconds > 0 ? autoDismissSeconds : 8
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in self?.dismissFromUser(key: key) }
        timer.resume()
        entry.dismissTimer = timer
        active[key] = entry
    }

    /// Dismissal originating from the overlay itself — the user closed it, tapped it to open,
    /// or its auto-dismiss timer fired. Unlike `dismiss(key:)` (used when the repositioner
    /// tears the overlay down to swap in a native banner), this first retires the real NC
    /// banner behind the overlay, so dismissing the custom banner doesn't reveal the native
    /// one underneath.
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
        let timeout = autoDismissSeconds > 0 ? autoDismissSeconds : 8
        for key in Array(active.keys) {
            active[key]?.dismissTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { [weak self] in self?.dismiss(key: key) }
            timer.resume()
            active[key]?.dismissTimer = timer
        }
    }

    func move(key: CFHashCode, axTopLeft: CGPoint, width: CGFloat) {
        guard let entry = active[key] else { return }
        let h = entry.panel.frame.size.height
        entry.panel.setFrame(Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: h)),
                             display: true, animate: false)
    }

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
