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
            HStack(alignment: .top, spacing: 12) {
                if let icon = content.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .padding(.top, 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(content.appName)
                            .font(.system(size: 11 * scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(timestampText)
                            .font(.system(size: 11 * scale))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    if !content.title.isEmpty {
                        Text(content.title)
                            .font(.system(size: 13 * scale, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !content.body.isEmpty {
                        Text(content.body)
                            .font(.system(size: 12 * scale))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10 * CGFloat(scale))
            .padding(.vertical, 7 * CGFloat(scale))
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
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(6)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHovering)

            // Show — bottom-right, hover only
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: max(8, 14 * CGFloat(scale)), style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: max(8, 14 * CGFloat(scale)), style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: max(8, 14 * CGFloat(scale)), style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity)
        .onHover { isHovering = $0 }
        .preferredColorScheme(.dark)
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
        let height = max(50 * scale, (11 + 13 * 2 + 12) * scale * 1.3 + 14 * scale)
        let frame = Self.axRect(axOrigin: axTopLeft, size: CGSize(width: width, height: height))
        let panel = makePanel(frame: frame, hostingView: hostingView)
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

    /// Restarts every active dismiss timer with a fresh countdown. Call on display wake so
    /// banners that arrived during sleep get their full display time from the moment of wake.
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

        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        return panel
    }

    static func axRect(axOrigin: CGPoint, size: CGSize) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsY = primaryHeight - axOrigin.y - size.height
        return NSRect(x: axOrigin.x, y: nsY, width: size.width, height: size.height)
    }
}
