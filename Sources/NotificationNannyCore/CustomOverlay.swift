import AppKit
import SwiftUI

// MARK: - Data

struct BannerContent {
    let appName: String
    let title: String
    let body: String
    let appIcon: NSImage?
}

// MARK: - View (no background — panel provides it)

struct CustomBannerView: View {
    let content: BannerContent
    let scale: Double
    let onDismiss: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    private var iconSize: CGFloat { 38 * CGFloat(scale) }

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 10 * CGFloat(scale)) {
                if let icon = content.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8 * CGFloat(scale), style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.appName)
                        .font(.system(size: 12 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                    if !content.title.isEmpty {
                        Text(content.title)
                            .font(.system(size: 14 * scale, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    if !content.body.isEmpty {
                        Text(content.body)
                            .font(.system(size: 13 * scale))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8 * CGFloat(scale))
            .padding(.vertical, 6 * CGFloat(scale))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(5)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHovering)

            Button { onOpen() } label: {
                Text("Show")
                    .font(.system(size: max(9, 10 * scale), weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(8)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .frame(maxWidth: .infinity)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Manager

@MainActor
final class CustomBannerManager {

    private struct Entry {
        let panel: NSPanel
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
        onOpen: @escaping () -> Void,
        key: CFHashCode
    ) {
        dismiss(key: key)

        let dismissHandler: () -> Void = { [weak self] in self?.dismiss(key: key) }
        let openAndDismiss: () -> Void = { [weak self] in onOpen(); self?.dismiss(key: key) }

        let displayScale = scale * 0.8
        let bannerWidth = width - 12

        // Fixed height — content never changes shape so no measurement needed
        let height = (56 * displayScale).rounded()
        let frame = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: bannerWidth, height: height))
        let radius = max(14.0, 20.0 * displayScale)

        // NSVisualEffectView owns the background — dark frosted glass guaranteed
        let blurView = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.appearance = NSAppearance(named: .darkAqua)
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = radius
        blurView.layer?.masksToBounds = true
        blurView.autoresizingMask = [.width, .height]

        // Optional colour tint layer between blur and content
        if backgroundColor != .clear {
            let tintView = NSView(frame: blurView.bounds)
            tintView.wantsLayer = true
            tintView.layer?.backgroundColor = NSColor(backgroundColor).withAlphaComponent(0.45).cgColor
            tintView.autoresizingMask = [.width, .height]
            blurView.addSubview(tintView)
        }

        // Border overlay
        let borderView = NSView(frame: blurView.bounds)
        borderView.wantsLayer = true
        borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        borderView.layer?.borderWidth = 0.5
        borderView.layer?.cornerRadius = radius
        borderView.autoresizingMask = [.width, .height]
        blurView.addSubview(borderView)

        // SwiftUI content — no background, purely text/icons on top of the blur
        let hostingView = NSHostingView(rootView: CustomBannerView(
            content: content,
            scale: displayScale,
            onDismiss: dismissHandler,
            onOpen: openAndDismiss
        ))
        hostingView.frame = blurView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        blurView.addSubview(hostingView)

        let panel = makePanel(frame: frame, contentView: blurView)
        panel.orderFront(nil)

        var entry = Entry(panel: panel)
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
        entry.panel.orderOut(nil)
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
        let currentSize = entry.panel.frame.size
        let newFrame = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: currentSize.height))
        entry.panel.setFrame(newFrame, display: true, animate: false)
    }

    private func makePanel(frame: NSRect, contentView: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
