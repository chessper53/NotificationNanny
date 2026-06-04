import AppKit
import SwiftUI

// MARK: - Data

struct BannerContent {
    let appName: String
    let title: String
    let body: String
    let appIcon: NSImage?
}

// MARK: - View

struct CustomBannerView: View {
    let content: BannerContent
    let scale: Double
    let onDismiss: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false
    @State private var minutesAgo: Int = 0
    private let appearedAt = Date()

    private var iconSize: CGFloat { 34 * CGFloat(scale) }

    private var timestampText: String {
        minutesAgo == 0 ? "now" : "\(minutesAgo)m ago"
    }

    var body: some View {
        ZStack {
            // Main content row — tappable
            HStack(alignment: .top, spacing: 8) {
                if let icon = content.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(content.appName)
                            .font(.system(size: 11 * scale, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(timestampText)
                            .font(.system(size: 11 * scale))
                            .foregroundStyle(.tertiary)
                    }
                    if !content.title.isEmpty {
                        Text(content.title)
                            .font(.system(size: 13 * scale, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !content.body.isEmpty {
                        Text(content.body)
                            .font(.system(size: 12 * scale))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                    minutesAgo = Int(Date().timeIntervalSince(appearedAt) / 60)
                }
            }

            // × — top-left, hover only
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(.secondary.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(5)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHovering)

            // Show — bottom-right, hover only
            Button { onOpen() } label: {
                Text("Show")
                    .font(.system(size: max(9, 10 * scale), weight: .semibold))
                    .foregroundStyle(Color(white: 0.1))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.78), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(7)
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
        opacity: Double,
        autoDismissSeconds: Double,
        onOpen: @escaping () -> Void,
        key: CFHashCode
    ) {
        dismiss(key: key)

        let dismissHandler: () -> Void = { [weak self] in self?.dismiss(key: key) }
        let openAndDismiss: () -> Void = { [weak self] in onOpen(); self?.dismiss(key: key) }

        let hostingView = NSHostingView(rootView: CustomBannerView(
            content: content,
            scale: scale,
            onDismiss: dismissHandler,
            onOpen: openAndDismiss
        ))
        // App name + up-to-2-line title + optional body, plus vertical padding.
        let height = max(73, (11 + 13 * 2 + 12) * scale * 1.3 + 22)
        let frame = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: height))
        let panel = makePanel(frame: frame, hostingView: hostingView)
        panel.alphaValue = CGFloat(max(0.1, min(1.0, opacity)))
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

    func updateOpacity(key: CFHashCode, opacity: Double) {
        active[key]?.panel.alphaValue = CGFloat(max(0.1, min(1.0, opacity)))
    }

    func move(key: CFHashCode, axTopLeft: CGPoint, width: CGFloat) {
        guard let entry = active[key] else { return }
        let currentSize = entry.panel.frame.size
        let newFrame = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: currentSize.height))
        entry.panel.setFrame(newFrame, display: true, animate: false)
    }

    private func makePanel(frame: NSRect, hostingView: NSView) -> NSPanel {
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

        // NSVisualEffectView with popover material + forced dark appearance matches the
        // system notification banner's frosted glass look.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true

        // Subtle edge highlight matching the system banner's depth cue.
        let border = CALayer()
        border.frame = blur.bounds
        border.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        border.borderWidth = 0.5
        border.cornerRadius = 14
        border.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        blur.layer?.addSublayer(border)

        hostingView.frame = blur.bounds
        hostingView.autoresizingMask = [.width, .height]
        blur.addSubview(hostingView)
        panel.contentView = blur
        return panel
    }

    static func axRect(axOrigin: CGPoint, size: CGSize) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsY = primaryHeight - axOrigin.y - size.height
        return NSRect(x: axOrigin.x, y: nsY, width: size.width, height: size.height)
    }
}
