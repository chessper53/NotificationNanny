import AppKit
import SwiftUI

// MARK: - Animation

package enum BannerAnimation: String, Codable, CaseIterable {
    case `default` = "Default"
    // case slide  = "Slide"
    // case bounce = "Bounce"
    // case fade   = "Fade"
    // case scale  = "Scale"
}

// MARK: - Data

struct BannerContent {
    let appName: String
    let title: String
    let body: String
    let appIcon: NSImage?
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
    let controller: BannerAnimationController
    let onDismiss: () -> Void
    let onOpen: () -> Void

    @State private var slideOffset: CGFloat = 150
    @State private var viewOpacity: Double = 1
    @State private var viewScale: CGFloat = 1
    @State private var isHovered = false

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
        .frame(maxWidth: .infinity)
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
        }
        .opacity(viewOpacity)
        .scaleEffect(viewScale)
        .offset(x: slideOffset)
        .onAppear { setupAnimations() }
    }

    private func setupAnimations() {
        switch animation {
        case .default:
            slideOffset = 150
            controller.slideOutClosure = {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { slideOffset = 150 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak controller] in controller?.dismissCompletion?() }
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { slideOffset = 0 }

        // case .bounce, .fade, .scale: commented out — not active
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

// MARK: - Manager

@MainActor
final class CustomBannerManager {

    private struct Entry {
        let panel: NSPanel
        let controller: BannerAnimationController
        var dismissTimer: DispatchSourceTimer?
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
        key: CFHashCode
    ) {
        dismiss(key: key)

        let controller = BannerAnimationController()
        let onDismissAction: () -> Void = { [weak self] in self?.dismiss(key: key) }
        let onOpenAction:   () -> Void = { [weak self] in onOpen(); self?.dismiss(key: key) }

        let s = CGFloat(scale)
        let bannerHeight: CGFloat = 62 * s
        let radius: CGFloat = 14 * s
        let frame  = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: bannerHeight))
        let bounds = CGRect(origin: .zero, size: frame.size)

        // Clip container — holds everything and applies the rounded mask.
        // Keeping the mask on a plain NSView (not NSVisualEffectView) avoids the
        // 1px fringe that appears when masksToBounds is set on a blur view directly.
        let clipView = NSView(frame: bounds)
        clipView.wantsLayer = true
        clipView.layer?.backgroundColor = NSColor.clear.cgColor
        clipView.autoresizingMask = [.width, .height]
        let maskLayer = CAShapeLayer()
        maskLayer.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        clipView.layer?.mask = maskLayer

        // Blur view fills the clip container — no rounding needed here.
        let blurView = NSVisualEffectView(frame: bounds)
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.appearance = NSAppearance(named: .darkAqua)
        blurView.autoresizingMask = [.width, .height]
        clipView.addSubview(blurView)

        let darkener = NSView(frame: bounds)
        darkener.wantsLayer = true
        darkener.layer?.backgroundColor = NSColor(white: 0, alpha: 0.28).cgColor
        darkener.autoresizingMask = [.width, .height]
        blurView.addSubview(darkener)

        if backgroundColor != .clear {
            let tint = NSView(frame: bounds)
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor(backgroundColor).withAlphaComponent(0.45).cgColor
            tint.autoresizingMask = [.width, .height]
            blurView.addSubview(tint)
        }

        let bannerView = CustomBannerView(
            content: content, scale: s, animation: animation, controller: controller,
            onDismiss: onDismissAction, onOpen: onOpenAction)
        let hosting = NSHostingView(rootView: bannerView)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        blurView.addSubview(hosting)

        let panel = makePanel(frame: frame, contentView: clipView)
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        var entry = Entry(panel: panel, controller: controller)
        let timeout = autoDismissSeconds > 0 ? autoDismissSeconds : 8
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in self?.dismiss(key: key) }
        timer.resume()
        entry.dismissTimer = timer
        active[key] = entry
    }

    func dismiss(key: CFHashCode) {
        guard let entry = active.removeValue(forKey: key) else { return }
        entry.dismissTimer?.cancel()
        let panel      = entry.panel
        let controller = entry.controller
        controller.dismissCompletion = {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
        if let slideOut = controller.slideOutClosure { slideOut() } else { panel.orderOut(nil) }
    }

    func dismissAll() {
        for key in Array(active.keys) { dismiss(key: key) }
    }

    func isActive(key: CFHashCode) -> Bool { active[key] != nil }

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
