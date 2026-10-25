import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    /// To the screen's edge, so the panel slides in from beyond it as the system's. Rows
    /// and what overhangs them grow with the panel's size; the inset from the edge doesn't.
    static func width(_ o: NCPanelOptions) -> CGFloat { (chrome + rowWidth) * o.scale + rightInset }

    /// Where the rows sit in a window frame of ours (AppKit coordinates): the inset from
    /// the screen's edge on the panel's side, the close button's room on the other and
    /// above.
    static func rowsRect(in frame: NSRect, options o: NCPanelOptions) -> NSRect {
        let width = rowWidth * o.scale
        let x = o.side == .right ? frame.maxX - rightInset - width : frame.minX + rightInset
        let top = frame.maxY - chrome * o.scale
        return NSRect(x: x, y: frame.minY, width: width, height: top - frame.minY)
    }

    private var options: NCPanelOptions { takeover?.options ?? NCPanelOptions() }

    /// Whether the panel is in or out, which its animation follows.
    let presentation = PanelPresentation()

    init(takeover: NCPanelTakeover) {
        self.takeover = takeover
        window = NCPanelWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width(NCPanelOptions()), height: 120),
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
        let view = CustomNCPanelView(takeover: takeover, presentation: presentation) { [weak self] height in
            self?.contentHeightChanged(height)
        }
        window.contentView = FirstMouseHostingView(rootView: view)
    }

    func show(on screen: NSScreen) {
        self.screen = screen
        layout()
        window.alphaValue = 1
        window.orderFrontRegardless()
        // Out first, then in on the next pass, so the animation has somewhere to start.
        presentation.shown = false
        DispatchQueue.main.async { [presentation] in presentation.shown = true }
    }

    /// Plays the panel's way out, then takes the window away.
    func hide(after outro: Double) {
        guard window.isVisible else { return }
        presentation.shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + outro + 0.05) { [weak self] in
            guard let self, !self.presentation.shown else { return }
            self.window.orderOut(nil)
        }
    }

    /// The tallest the panel can be on its screen.
    var maxHeight: CGFloat {
        guard let screen else { return 600 }
        return screen.frame.height - Self.topInset - Self.rightInset + Self.chrome * options.scale * 2
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
        let o = options
        let height = min(contentHeight, maxHeight)
        let width = Self.width(o)
        let top = screen.frame.maxY - Self.topInset + Self.chrome * o.scale
        let x = o.side == .right ? screen.frame.maxX - width : screen.frame.minX
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
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

/// In or out: the panel's animation, chosen in Settings, plays between the two.
@MainActor
final class PanelPresentation: ObservableObject {
    @Published var shown = false
}

// MARK: - View

/// The panel's size, 1 being the system's; every measurement below is multiplied by it.
private struct PanelScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var panelScale: CGFloat {
        get { self[PanelScaleKey.self] }
        set { self[PanelScaleKey.self] = newValue }
    }
}

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
    /// Notification Center darkens what is behind its list, in both appearances alike:
    /// the whole column by 12% (fading in over the first 40 points from 7%), and behind
    /// the rows themselves by 10% more. Measured against the same gray backdrop under the
    /// real panel and ours (scripts/panel-lab/compare.sh); the rows' glass shows it, which
    /// is why they look darker in the panel than as banners.
    static let columnDim: Double = 0.12
    static let columnDimTop: Double = 0.07
    static let columnFade: CGFloat = 40
    static let rowsDim: Double = 0.10
    static let stackLayerDim: Double = 0.09
}

struct CustomNCPanelView: View {
    @ObservedObject var takeover: NCPanelTakeover
    @ObservedObject var presentation: PanelPresentation
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
        let o = takeover.options
        let s = o.scale
        let chrome = CustomNCPanelController.chrome * s
        let edge = CustomNCPanelController.rightInset
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if o.appFilter, apps.count > 1 {
                    appFilter.padding(.bottom, NCPanelMetrics.rowGap * s)
                }
                if !takeover.widgets.isEmpty {
                    VStack(spacing: NCPanelMetrics.rowGap * s) {
                        ForEach(takeover.widgets) { widget in WidgetView(widget: widget, takeover: takeover) }
                    }
                    .padding(.bottom, NCPanelMetrics.rowGap * s)
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
            .background(Color.black.opacity(NCPanelMetrics.rowsDim))
            .environment(\.panelScale, s)
            // The inset from the screen's edge on the panel's side, the close button's
            // room on the other.
            .padding([.top, .bottom], chrome)
            .padding(.leading, o.side == .right ? chrome : edge)
            .padding(.trailing, o.side == .right ? edge : chrome)
            .frame(width: CustomNCPanelController.width(o), alignment: .topLeading)
            .background(GeometryReader { g in
                Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
            })
        }
        .frame(width: CustomNCPanelController.width(o), height: listHeight)
        .background(alignment: .top) { ColumnDim() }
        .modifier(PanelMotion(shown: presentation.shown, animation: o.animation, side: o.side))
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

/// What Notification Center lays over the desktop behind its list; see NCPanelMetrics.
private struct ColumnDim: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(NCPanelMetrics.columnDimTop), .black.opacity(NCPanelMetrics.columnDim)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: NCPanelMetrics.columnFade)
            Color.black.opacity(NCPanelMetrics.columnDim)
        }
    }
}

/// The panel's way in and out: the banners' animations, applied to the whole list.
private struct PanelMotion: ViewModifier {
    let shown: Bool
    let animation: BannerAnimation
    let side: NCPanelSide

    func body(content: Content) -> some View {
        let t = shown ? BannerAnimation.Transform() : animation.hidden
        // On the left, sideways motion is mirrored: the default comes in from that edge.
        let x = side == .right ? t.x : -t.x
        content
            .opacity(t.opacity)
            .scaleEffect(t.scale, anchor: side == .right ? .topTrailing : .topLeading)
            .rotationEffect(.degrees(side == .right ? t.rotation : -t.rotation))
            .offset(x: x, y: t.y)
            .animation(shown ? animation.intro : animation.outro, value: shown)
    }
}

/// A heading over the desktop, as Notification Center draws its own and an expanded
/// stack's: bold, with its buttons on the right.
private struct Heading<Buttons: View>: View {
    let title: String
    var isFirst = false
    @ViewBuilder let buttons: () -> Buttons
    @Environment(\.panelScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            // White in both appearances: it stands on the desktop, as the system's does.
            Text(title)
                .font(.system(size: NCPanelMetrics.headingFont * s, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .lineLimit(1)
                .padding(.leading, 1)
            Spacer(minLength: 0)
            buttons()
        }
        .frame(height: NCPanelMetrics.headingHeight * s)
        .padding(.top, isFirst ? 0 : (NCPanelMetrics.headingAbove - NCPanelMetrics.rowGap) * s)
        .padding(.bottom, NCPanelMetrics.headingBelow * s)
    }
}

/// The system's round glass button beside a heading: Clear, Clear All.
private struct RoundButton: View {
    let symbol: String
    let action: () -> Void
    @Environment(\.panelScale) private var s
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8 * s, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: NCPanelMetrics.roundButton * s, height: NCPanelMetrics.roundButton * s)
                .background(BannerGlass(shape: Circle(), cornerRadius: NCPanelMetrics.roundButton * s / 2, scale: s))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A pill beside an expanded stack's heading: Show Less.
private struct PillButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.panelScale) private var s
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11 * s))
                .foregroundStyle(.secondary)
                .frame(width: NCPanelMetrics.showLessWidth * s, height: NCPanelMetrics.roundButton * s)
                .background(BannerGlass(shape: Capsule(), cornerRadius: NCPanelMetrics.roundButton * s / 2, scale: s))
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
    @Environment(\.panelScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: NCPanelMetrics.rowGap * s) {
            if group.expanded {
                Heading(title: group.appName) {
                    PillButton(title: SystemStrings.showLess) { takeover.collapse(group) }
                    RoundButton(symbol: "xmark") { takeover.clear(group) }
                }
                .padding(.bottom, -NCPanelMetrics.rowGap * s)
            }
            ForEach(group.rows) { row in
                RowView(row: row, takeover: takeover)
                // A collapsed stack: the edges of the cards behind it, under its own.
                if row.isStack {
                    StackEdges(tint: takeover.tint(row.appName)).padding(.top, -NCPanelMetrics.rowGap * s)
                }
            }
        }
        .padding(.bottom, (NCPanelMetrics.rowGap + (group.expanded ? NCPanelMetrics.stackPeek : 0)) * s)
    }
}

/// A notification as a banner, the system's way: the same card the custom banner draws,
/// with the banners' tint, text colour and blur.
private struct RowView: View {
    let row: NCPanelRow
    @ObservedObject var takeover: NCPanelTakeover
    @State private var hovering = false
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.panelScale) private var s

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
        BannerCard(content: content, scale: s, tint: takeover.tint(row.appName), textColor: options.textColor,
                   redactContent: options.redact, hovered: hovering, edge: .panelRow,
                   onOpen: { takeover.activate(row) },
                   onAction: { takeover.perform($0, on: row) },
                   onDetails: { takeover.toggleDetails(row) })
            .frame(width: CustomNCPanelController.rowWidth * s, height: row.height * s)
            .overlay(alignment: .topTrailing) {
                // Not the system's: when each arrived, if asked for in Settings. Out of the
                // way of the hover controls, which take its place.
                if !hovering, !row.expanded, let arrival = takeover.arrival(of: row) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(NotificationTimeText.text(for: arrival, now: context.date, locale: loc.locale))
                            .font(.system(size: 11 * s).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 9 * s).padding(.trailing, 14 * s)
                }
            }
            .overlay(alignment: .topLeading) {
                if hovering {
                    CloseButton { takeover.close(row) }
                        .offset(x: CustomBannerView.Metrics.closeOrigin.x * s, y: CustomBannerView.Metrics.closeOrigin.y * s)
                }
            }
            .activeHover { inside in withAnimation(.easeInOut(duration: 0.15)) { hovering = inside } }
    }
}

/// The two cards a collapsed stack shows under its own, glass like it and each narrower,
/// one 8 point strip each. Each shows only its own strip: on the system's, the nearer
/// card hides the one behind it, where two layers of glass would come out twice as bright.
/// Measured: each as bright as the card, ending in its bright edge (compare.sh).
private struct StackEdges: View {
    let tint: Color
    @Environment(\.panelScale) private var s
    var body: some View {
        VStack(spacing: 0) {
            layer(inset: 8 * s)
            layer(inset: 16 * s)
        }
        .frame(width: CustomNCPanelController.rowWidth * s, height: NCPanelMetrics.stackPeek * s)
    }

    private func layer(inset: CGFloat) -> some View {
        let radius = CustomBannerView.Metrics.cornerRadius * s
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Glass this thin, right under a card, comes out brighter than a card: it takes
        // in the card above it. The system's are as bright as the card; 9% less brings
        // them there in both appearances (compare.sh).
        return BannerGlass(shape: shape, cornerRadius: radius, scale: s, tint: tint)
            .overlay(shape.fill(Color.black.opacity(NCPanelMetrics.stackLayerDim)))
            .frame(height: 40 * s)
            .padding(.horizontal, inset)
            .frame(height: NCPanelMetrics.stackPeek / 2 * s, alignment: .bottom)
            .clipped()
    }
}

/// The banner's close button, the same as the custom banner's.
private struct CloseButton: View {
    let action: () -> Void
    @Environment(\.panelScale) private var s
    var body: some View {
        let d = CustomBannerView.Metrics.closeDiameter * s
        return Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8 * s, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: d, height: d)
                .background(BannerGlass(shape: Circle(), cornerRadius: d / 2, scale: s))
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

    @Environment(\.panelScale) private var s

    var body: some View {
        let size = CGSize(width: widget.frameInWindow.width * s, height: widget.frameInWindow.height * s)
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
        // Without an icon of its own, the generic app icon, as the system shows.
        Image(nsImage: AppIconCache.shared.icon(for: appName) ?? NSWorkspace.shared.icon(for: .applicationBundle))
            .resizable().interpolation(.high).frame(width: size, height: size)
    }
}
