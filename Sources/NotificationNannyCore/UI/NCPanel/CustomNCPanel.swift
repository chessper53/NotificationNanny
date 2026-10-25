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

    /// Notification Center's column, measured on 27.0 (scripts/panel-lab `panel-shots`):
    /// rows 344 points wide, 16 from the screen's right edge, the first 46 from its top.
    static let rowWidth: CGFloat = 344
    static let rightInset: CGFloat = 16
    static let topInset: CGFloat = 46
    /// Room around the rows for what overhangs them: a row's close button.
    static let chrome: CGFloat = CustomBannerView.Metrics.chromeInset
    static var width: CGFloat { rowWidth + chrome * 2 }

    init(takeover: NCPanelTakeover) {
        self.takeover = takeover
        window = NCPanelWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        // The rows are glass and cast none, as the system's don't.
        window.hasShadow = false
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
        return screen.frame.height - Self.topInset - Self.rightInset + Self.chrome * 2
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
        let height = min(contentHeight, maxHeight)
        let top = screen.frame.maxY - Self.topInset + Self.chrome
        let frame = NSRect(x: screen.frame.maxX - Self.rightInset - Self.rowWidth - Self.chrome, y: top - height,
                           width: Self.width, height: height)
        window.setFrame(frame, display: true)
    }
}

/// An opaque window between Notification Center's panel and ours, while the real panel
/// sits under ours to have its widgets captured. Ours covers it almost always; this
/// covers what ours doesn't, so no part of the real panel ever shows.
@MainActor
final class NCPanelCover {
    private let window: NSPanel

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Notification Center's window is at 21, ours at the status bar's 25.
        window.level = NSWindow.Level(rawValue: 22)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let fill = NSHostingView(rootView: RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.nannyWindow))
        window.contentView = fill
    }

    func show(axRect: CGRect, below ours: NSWindow) {
        guard let primary = NSScreen.screens.first else { return }
        let frame = NSRect(x: axRect.minX, y: primary.frame.maxY - axRect.maxY, width: axRect.width, height: axRect.height)
        window.setFrame(frame, display: true)
        window.order(.below, relativeTo: ours.windowNumber)
    }

    func hide() { window.orderOut(nil) }
}

// MARK: - View

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Notification Center's list, drawn as the system draws it: every row is a banner, rows
/// stand apart on the desktop with no panel behind them, and headings sit over the desktop
/// in bold. Spacing measured on 27.0 (scripts/panel-lab `panel-shots`).
enum NCPanelMetrics {
    static let rowGap: CGFloat = 6
    /// A collapsed stack shows the edges of the cards behind it under its own.
    static let stackPeek: CGFloat = 16
    /// A heading (Notification Center, or an app's expanded stack) and what is around it.
    static let headingAbove: CGFloat = 23
    static let headingBelow: CGFloat = 8
    static let headingHeight: CGFloat = 20
    static let headingFont: CGFloat = 15
    static let showLessWidth: CGFloat = 73
    static let roundButton: CGFloat = 20
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if takeover.options.appFilter, apps.count > 1 {
                    appFilter.padding(.bottom, NCPanelMetrics.rowGap)
                }
                if !takeover.widgets.isEmpty {
                    VStack(spacing: NCPanelMetrics.rowGap) {
                        ForEach(takeover.widgets) { widget in WidgetView(widget: widget, takeover: takeover) }
                    }
                    .padding(.bottom, NCPanelMetrics.rowGap)
                }
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    if let title = section.title {
                        Heading(title: title, isFirst: index == 0 && takeover.widgets.isEmpty) {
                            RoundButton(symbol: "xmark") { takeover.clearAll(section) }
                        }
                    }
                    ForEach(section.groups) { group in GroupView(group: group, takeover: takeover) }
                }
            }
            .padding(CustomNCPanelController.chrome)
            .frame(width: CustomNCPanelController.width, alignment: .topLeading)
            .background(GeometryReader { g in
                Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
            })
        }
        .frame(width: CustomNCPanelController.width, height: listHeight)
        .onPreferenceChange(ContentHeightKey.self) { h in
            contentHeight = h
            onHeight(min(h, maxHeight))
        }
        .onChange(of: apps) { _, apps in if let f = filter, !apps.contains(f) { filter = nil } }
    }

    @State private var contentHeight: CGFloat = 0
    private var maxHeight: CGFloat {
        (NSScreen.main?.frame.height ?? 900) - CustomNCPanelController.topInset - CustomNCPanelController.rightInset
    }
    private var listHeight: CGFloat { max(min(contentHeight, maxHeight), 1) }

    /// Not part of the system's panel; only shown when asked for in Settings.
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
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(selected ? 0.25 : 0.12)))
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// A heading over the desktop, as Notification Center draws its own and an expanded
/// stack's: bold, with its buttons on the right.
private struct Heading<Buttons: View>: View {
    let title: String
    var isFirst = false
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: NCPanelMetrics.headingFont, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.leading, 1)
            Spacer(minLength: 0)
            buttons()
        }
        .frame(height: NCPanelMetrics.headingHeight)
        .padding(.top, isFirst ? 0 : NCPanelMetrics.headingAbove - NCPanelMetrics.rowGap)
        .padding(.bottom, NCPanelMetrics.headingBelow)
    }
}

/// The system's round glass button beside a heading: Clear, Clear All.
private struct RoundButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: NCPanelMetrics.roundButton, height: NCPanelMetrics.roundButton)
                .background(Circle().fill(Color.primary.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A pill beside an expanded stack's heading: Show Less.
private struct PillButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: NCPanelMetrics.showLessWidth, height: NCPanelMetrics.roundButton)
                .background(Capsule().fill(Color.primary.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One app's notifications: a single row, a collapsed stack, or an expanded stack under
/// its heading.
private struct GroupView: View {
    let group: NCPanelSnapshot.Group
    @ObservedObject var takeover: NCPanelTakeover

    var body: some View {
        VStack(alignment: .leading, spacing: NCPanelMetrics.rowGap) {
            if group.expanded {
                Heading(title: group.appName) {
                    PillButton(title: SystemStrings.showLess) { takeover.collapse(group) }
                    RoundButton(symbol: "xmark") { takeover.clear(group) }
                }
                .padding(.bottom, -NCPanelMetrics.rowGap)
            }
            ForEach(group.rows) { row in
                RowView(row: row, takeover: takeover)
                // A collapsed stack: the edges of the cards behind it, under its own.
                if row.isStack { StackEdges().padding(.top, -NCPanelMetrics.rowGap) }
            }
        }
        .padding(.bottom, NCPanelMetrics.rowGap + (group.expanded ? NCPanelMetrics.stackPeek : 0))
    }
}

/// A notification as a banner, the system's way: the same card the custom banner draws,
/// with the banners' tint, text colour and blur.
private struct RowView: View {
    let row: NCPanelRow
    @ObservedObject var takeover: NCPanelTakeover
    @State private var hovering = false
    @ObservedObject private var loc = LocalizationManager.shared

    private var content: BannerContent {
        var c = BannerContent(appName: row.appName, title: row.title, subtitle: row.subtitle, body: row.body,
                              appIcon: AppIconCache.shared.icon(for: row.appName))
        c.actions = row.actions
        c.expanded = row.expanded
        c.reply = row.reply
        c.replyPlaceholder = row.replyPlaceholder
        return c
    }

    var body: some View {
        let options = takeover.options
        BannerCard(content: content, scale: 1, tint: takeover.tint(row.appName), textColor: options.textColor,
                   redactContent: options.redact, hovered: hovering,
                   onOpen: { takeover.activate(row) },
                   onAction: { takeover.perform($0, on: row) },
                   onDetails: { takeover.toggleDetails(row) })
            .frame(width: CustomNCPanelController.rowWidth, height: row.height)
            .overlay(alignment: .topTrailing) {
                // Not the system's: when each arrived, if asked for in Settings. Out of the
                // way of the hover controls, which take its place.
                if !hovering, !row.expanded, let arrival = takeover.arrival(of: row) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(NotificationTimeText.text(for: arrival, now: context.date, locale: loc.locale))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 9).padding(.trailing, 14)
                }
            }
            .overlay(alignment: .topLeading) {
                if hovering {
                    CloseButton { takeover.close(row) }
                        .offset(x: CustomBannerView.Metrics.closeOrigin.x, y: CustomBannerView.Metrics.closeOrigin.y)
                }
            }
            .activeHover { inside in withAnimation(.easeInOut(duration: 0.15)) { hovering = inside } }
    }
}

/// The two cards a collapsed stack shows under its own, each narrower and fainter: only
/// their bottoms, in the strip below the front card, since the cards are glass and
/// anything behind one shows through it.
private struct StackEdges: View {
    var body: some View {
        let peek = NCPanelMetrics.stackPeek
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07))
                .frame(height: 40).padding(.horizontal, 16).offset(y: peek - 40)
            RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Color.primary.opacity(0.11))
                .frame(height: 40).padding(.horizontal, 8).offset(y: peek / 2 - 40)
        }
        .frame(width: CustomNCPanelController.rowWidth, height: peek, alignment: .top)
        .clipped()
    }
}

/// The banner's close button, the same as the custom banner's.
private struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: CustomBannerView.Metrics.closeDiameter, height: CustomBannerView.Metrics.closeDiameter)
                .background(Circle().fill(.regularMaterial))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A picture of a real widget, sized as Notification Center draws it. A click goes to the
/// real one, at the same spot.
private struct WidgetView: View {
    let widget: NCWidget
    @ObservedObject var takeover: NCPanelTakeover

    var body: some View {
        let size = widget.frameInWindow.size
        Group {
            if let image = widget.image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.06))
            }
        }
        .frame(width: size.width, height: size.height)
        // The capture's corners hold whatever was behind the widget's rounded ones.
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            takeover.click(widget, at: CGPoint(x: min(max(location.x / size.width, 0), 1),
                                               y: min(max(location.y / size.height, 0), 1)))
        }
    }
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
