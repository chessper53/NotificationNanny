import AppKit
import SwiftUI

/// The window our Notification Center list is drawn in.
///
/// It never becomes key or main: Notification Center closes its panel when anything
/// else takes focus. Clicks reach it through `PanelClickRouter`, which sends them to the
/// window directly, so the hosting view has to take the first click.
final class NCPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CustomNCPanelController {
    let window: NCPanelWindow
    private weak var takeover: NCPanelTakeover?
    private var screen: NSScreen?
    private var contentHeight: CGFloat = 120

    static let width: CGFloat = 372
    /// From the screen's edge and the menu bar, as Notification Center's panel sits.
    private static let margin: CGFloat = 8

    init(takeover: NCPanelTakeover) {
        self.takeover = takeover
        window = NCPanelWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // scripts/panel-lab checks both appearances without switching the system's.
        switch ProcessInfo.processInfo.environment["NN_LAB_PANEL_APPEARANCE"] {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        let view = CustomNCPanelView(takeover: takeover) { [weak self] height in self?.contentHeightChanged(height) }
        window.contentView = FirstMouseHostingView(rootView: view)
    }

    func show(on screen: NSScreen) {
        self.screen = screen
        layout()
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 0
        }, completionHandler: { [weak window] in
            MainActor.assumeIsolated { window?.orderOut(nil) }
        })
    }

    /// The tallest the panel can be on its screen.
    var maxHeight: CGFloat {
        guard let screen else { return 600 }
        return screen.visibleFrame.height - Self.margin * 2
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        layout()
    }

    /// Exactly as tall as what it shows: the click router takes every click inside the
    /// window, so a transparent margin would swallow clicks meant for what is below.
    private func layout() {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let height = min(contentHeight, maxHeight)
        let frame = NSRect(x: visible.maxX - Self.width - Self.margin, y: visible.maxY - Self.margin - height,
                           width: Self.width, height: height)
        window.setFrame(frame, display: true)
    }
}

// MARK: - View

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct CustomNCPanelView: View {
    @ObservedObject var takeover: NCPanelTakeover
    let onHeight: (CGFloat) -> Void
    @State private var filter: String?

    private var apps: [String] {
        var seen: [String] = []
        for section in takeover.snapshot.sections {
            for group in section.groups where !seen.contains(group.appName) { seen.append(group.appName) }
        }
        return seen
    }

    private var sections: [NCPanelSnapshot.Section] {
        guard let filter else { return takeover.snapshot.sections }
        return takeover.snapshot.sections.compactMap { section in
            var s = section
            s.groups = section.groups.filter { $0.appName == filter }
            return s.groups.isEmpty ? nil : s
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if apps.count > 1 { appFilter }
            if takeover.snapshot.isEmpty {
                LocalizedText("No notifications")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sections) { section in sectionView(section) }
                    }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                    })
                }
                .frame(height: listHeight)
            }
        }
        .padding(12)
        .frame(width: CustomNCPanelController.width, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.nannyWindow))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.nannyRaised(0.1)))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in
            Color.clear.onAppear { onHeight(g.size.height) }
                .onChange(of: g.size.height) { _, h in onHeight(h) }
        })
        .onPreferenceChange(ContentHeightKey.self) { listContentHeight = $0 }
        .onChange(of: apps) { _, apps in if let f = filter, !apps.contains(f) { filter = nil } }
    }

    @State private var listContentHeight: CGFloat = 0

    /// The list grows with its content up to what the screen leaves, then scrolls.
    private var listHeight: CGFloat {
        let screenRoom = (NSScreen.main?.visibleFrame.height ?? 900) - 140
        return min(max(listContentHeight, 60), screenRoom)
    }

    private var header: some View {
        HStack(spacing: 8) {
            LocalizedText("Notifications").font(.headline).foregroundStyle(Color.nannyStrong)
            Spacer()
        }
    }

    private var appFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(nil, label: AnyView(LocalizedText("All")))
                ForEach(apps, id: \.self) { app in
                    chip(app, label: AnyView(HStack(spacing: 4) {
                        AppIcon(appName: app, size: 14)
                        Text(app).lineLimit(1)
                    }))
                }
            }
        }
    }

    private func chip(_ app: String?, label: AnyView) -> some View {
        let selected = filter == app
        return Button { filter = app } label: {
            label
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(selected ? Color.nannyWash(0.3) : Color.nannyRaised(0.06)))
                .foregroundStyle(selected ? Color.nannyAccent : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionView(_ section: NCPanelSnapshot.Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = section.title {
                HStack {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    textButton("Clear All") { takeover.clearAll(section) }
                }
            }
            ForEach(section.groups) { group in GroupCard(group: group, takeover: takeover) }
        }
    }
}

private extension Color {
    /// Opaque, so the card behind a stack doesn't show through.
    static let nannyCard = nannyAdaptive(light: .white, dark: NSColor(white: 0.16, alpha: 1))
    static let nannyCardBehind = nannyAdaptive(light: NSColor(white: 0.84, alpha: 1), dark: NSColor(white: 0.21, alpha: 1))
}

private func textButton(_ key: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        LocalizedText(key).font(.caption.weight(.medium)).foregroundStyle(Color.nannyAccent)
    }
    .buttonStyle(.plain)
}

private struct AppIcon: View {
    let appName: String
    let size: CGFloat
    var body: some View {
        if let icon = AppIconCache.shared.icon(for: appName) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "bell.fill").font(.system(size: size * 0.6))
                .frame(width: size, height: size).foregroundStyle(.secondary)
        }
    }
}

/// One app's notifications: a single row, a collapsed stack, or an expanded stack with
/// its header. Laid out like Notification Center's, so it reads the same.
private struct GroupCard: View {
    let group: NCPanelSnapshot.Group
    @ObservedObject var takeover: NCPanelTakeover

    var body: some View {
        let tint = takeover.tint(group.appName)
        let stacked = group.rows.first?.isStack == true
        VStack(alignment: .leading, spacing: 0) {
            if group.expanded {
                HStack(spacing: 6) {
                    AppIcon(appName: group.appName, size: 16)
                    Text(group.appName).font(.caption.weight(.semibold))
                    Text("\(group.rows.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    textButton("Show less") { takeover.collapse(group) }
                    textButton("Clear") { takeover.clear(group) }
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
            }
            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, group.expanded ? 10 : 52) }
                RowView(row: row, showsIcon: !group.expanded, takeover: takeover)
            }
        }
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.nannyCard))
        .overlay(alignment: .leading) {
            // The app's own tint from its exception group, as a flat edge.
            if let tint {
                RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 3).padding(.vertical, 8)
            }
        }
        // A collapsed stack shows the edge of the card behind it, as macOS does.
        .background(alignment: .bottom) {
            if stacked {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.nannyCardBehind)
                    .frame(height: 20).padding(.horizontal, 9).offset(y: 6)
            }
        }
        .padding(.bottom, stacked ? 6 : 0)
    }
}

private struct RowView: View {
    let row: NCPanelRow
    let showsIcon: Bool
    @ObservedObject var takeover: NCPanelTakeover
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsIcon { AppIcon(appName: row.appName, size: 32) }
            VStack(alignment: .leading, spacing: 1) {
                if showsIcon {
                    Text(row.appName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if !row.title.isEmpty {
                    Text(row.title).font(.callout.weight(.semibold)).foregroundStyle(Color.nannyStrong).lineLimit(1)
                }
                if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.callout).lineLimit(1)
                }
                if !row.body.isEmpty {
                    Text(row.body).font(.callout).foregroundStyle(.secondary).lineLimit(hovering ? 8 : 2)
                }
            }
            Spacer(minLength: 0)
            Button { takeover.close(row) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.nannyRaised(hovering ? 0.16 : 0.08)))
                    .foregroundStyle(hovering ? Color.nannyStrong : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { takeover.activate(row) }
        .onHover { hovering = $0 }
    }
}
