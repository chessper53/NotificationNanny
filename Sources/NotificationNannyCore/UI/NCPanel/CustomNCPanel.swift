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

/// A hosting view that takes the click that would otherwise only make its window key.
/// Our panel never becomes key; Settings stops being key while Notification Center's
/// panel is open, and the click router hands it clicks then (dragging the panel's place).
package class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override package func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FirstMouseHostingView<Content: View>: FirstClickHostingView<Content> {
    /// A right click, at its place in the view (top left origin).
    var onRightClick: ((CGPoint) -> Void)?

    override func mouseDown(with event: NSEvent) { // DEBUG-CLICK
        if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" {
            FileHandle.standardError.write(Data("[panel view] down at \(event.locationInWindow)\n".utf8))
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let onRightClick else { return super.rightMouseDown(with: event) }
        let p = convert(event.locationInWindow, from: nil)
        onRightClick(CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y))
    }
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
    static func width(_ o: NCPanelOptions) -> CGFloat {
        // In the middle there is no edge to reach, only the close button's room each side.
        o.side == .center ? (chrome * 2 + rowWidth) * o.scale : (chrome + rowWidth) * o.scale + rightInset
    }

    /// Where the rows sit in a window frame of ours (AppKit coordinates): the inset from
    /// the screen's edge on the panel's side, the close button's room on the other and
    /// above.
    static func rowsRect(in frame: NSRect, options o: NCPanelOptions) -> NSRect {
        let width = rowWidth * o.scale
        let x: CGFloat
        switch o.side {
        case .right: x = frame.maxX - rightInset - width
        case .center: x = frame.midX - width / 2
        case .left: x = frame.minX + rightInset
        }
        let top = frame.maxY - chrome * o.scale
        return NSRect(x: x, y: frame.minY, width: width, height: top - frame.minY)
    }

    /// The offset across that the screen has room for: the rows never come closer to
    /// either edge than the system's do to the right one. Clamped here rather than when
    /// it is set, as the same offset is used on screens of every width.
    static func xOffset(_ o: NCPanelOptions, on frame: NSRect) -> CGFloat {
        let width = rowWidth * o.scale
        let base: CGFloat
        switch o.side {
        case .right: base = frame.maxX - rightInset - width
        case .center: base = frame.midX - width / 2
        case .left: base = frame.minX + rightInset
        }
        let lowest = frame.minX + rightInset
        let highest = max(lowest, frame.maxX - rightInset - width)
        return min(max(base + o.xOffset, lowest), highest) - base
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
        let hitMap = NCPanelHitMap()
        let view = CustomNCPanelView(takeover: takeover, presentation: presentation, onHeight: { [weak self] height in
            self?.contentHeightChanged(height)
        }, hitMap: hitMap, maxHeightOnScreen: { [weak self] in self?.maxHeight ?? 600 })
        let host = FirstMouseHostingView(rootView: view)
        // The window's size is the controller's (layout()), never the content's.
        host.sizingOptions = []
        // A right click on a row opens its menu where it was clicked, as on the system's.
        host.onRightClick = { [weak takeover] point in
            guard let takeover, let id = hitMap.row(at: point),
                  let row = takeover.snapshot.sections.lazy.flatMap({ $0.groups }).flatMap({ $0.rows }).first(where: { $0.id == id })
            else { return }
            takeover.showMenu(for: row, withAppActions: true, at: point, trailing: false)
        }
        window.contentView = host
    }

    func show(on screen: NSScreen) {
        self.screen = screen
        layout()
        window.alphaValue = 1
        window.orderFrontRegardless()
        if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" { // DEBUG-CLICK
            FileHandle.standardError.write(Data("[panel window] shown uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
        }
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
        return screen.frame.height - Self.topInset - options.topOffset - Self.rightInset + Self.chrome * options.scale * 2
    }

    /// Places it again, for a change of its place or size while it is open.
    func relayout() { layout() }

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
        let top = screen.frame.maxY - Self.topInset - o.topOffset + Self.chrome * o.scale
        var x: CGFloat
        switch o.side {
        case .right: x = screen.frame.maxX - width
        case .center: x = screen.frame.midX - width / 2
        case .left: x = screen.frame.minX
        }
        x += Self.xOffset(o, on: screen.frame)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        window.setFrame(frame, display: true)
        if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" { // DEBUG-CLICK
            FileHandle.standardError.write(Data("[panel window] height \(Int(height)) uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
        }
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

/// Where each row is in the panel's view, for a right click to find it.
private struct RowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The panel view's coordinate space: the window's content, top left origin. Menus and
/// right clicks are placed in it.
enum NCPanelSpace {
    static let name = "ncPanel"
}

/// Hands a view's frame in the panel's space to `frame`, as it changes.
private struct PanelFrameReader: ViewModifier {
    @Binding var frame: CGRect
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .named(NCPanelSpace.name)) }
                .onChange(of: g.frame(in: .named(NCPanelSpace.name))) { _, f in frame = f }
        })
    }
}

/// Notification Center's list, drawn as the system draws it: every row is a banner, rows
/// stand apart on the desktop with no panel behind them, and headings sit over the desktop
/// in bold. Spacing measured on 27.0 (scripts/panel-lab `panel-shots`, `tree`).
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
    /// Under the list: Edit Widgets (87 wide) and the Clear Notifications ✕, both 24 high,
    /// 8 apart, centred on the column, 16 under what is above them.
    static let footerAbove: CGFloat = 16
    static let footerHeight: CGFloat = 24
    static let footerGap: CGFloat = 8
    static let editWidgetsWidth: CGFloat = 87
    /// Notification Center darkens what is behind its list, in both appearances alike:
    /// the column by 12% and behind the rows by 10% more, 21% in all (measured against
    /// the same gray backdrop under the real panel and ours, scripts/panel-lab/compare.sh).
    /// It shows through the rows' glass, which is why they look darker in the panel than
    /// as banners. Ours darkens only under each row and button, exactly where their glass
    /// shows it: a dimmed column read as a dark box over the windows behind the panel.
    static let behindGlass: Double = 0.21
    static let stackLayerDim: Double = 0.09
}

/// The darkening Notification Center has behind its list, under one piece of glass.
private extension View {
    func panelBackdrop<S: Shape>(_ shape: S) -> some View {
        background(shape.fill(Color.black.opacity(NCPanelMetrics.behindGlass)))
    }
}

struct CustomNCPanelView: View {
    @ObservedObject var takeover: NCPanelTakeover
    @ObservedObject var presentation: PanelPresentation
    let onHeight: (CGFloat) -> Void
    /// Rows by where they are, for a right click.
    let hitMap: NCPanelHitMap
    /// The tallest the panel can be: its screen's height under where it starts, which the
    /// window knows. Taken from there so the list and its window never disagree; a list
    /// taller than its window was cut off wrong when the panel was placed low.
    let maxHeightOnScreen: () -> CGFloat
    @State private var filter: String?
    @State private var contentHeight: CGFloat = 0
    @State private var menuBottom: CGFloat = 0

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
        let width = CustomNCPanelController.width(o)
        // Taller while a menu hangs below the list, so it is in the window and gets clicks.
        let height = max(listHeight, min(menuBottom, maxHeight), 1)
        return ZStack(alignment: .topLeading) {
            list(o)
                .modifier(PanelMotion(shown: presentation.shown, animation: o.animation, side: o.side))
            if let menu = takeover.menu {
                menuLayer(menu, width: width, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        // Pinned to the window's top whatever height it has: the window's size comes from
        // the controller, a step ahead of this view's own idea of its height right after
        // opening, and the content was centred in the window meanwhile. It then jumped up
        // under the pointer, and a click made then was lost.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: NCPanelSpace.name)
        .onPreferenceChange(ContentHeightKey.self) { h in
            contentHeight = h
            onHeight(min(max(h, menuBottom), maxHeight))
        }
        .onPreferenceChange(RowFramesKey.self) { hitMap.rowFrames = $0 }
        .onChange(of: takeover.menu) { _, menu in
            if menu == nil {
                menuBottom = 0
                onHeight(min(contentHeight, maxHeight))
            }
        }
        .onChange(of: apps) { _, apps in if let f = filter, !apps.contains(f) { filter = nil } }
    }

    private func list(_ o: NCPanelOptions) -> some View {
        let s = o.scale
        let chrome = CustomNCPanelController.chrome * s
        let edge = CustomNCPanelController.rightInset
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if o.appFilter, apps.count > 1 {
                    AppFilterBar(apps: apps, filter: $filter).padding(.bottom, NCPanelMetrics.headingBelow * s)
                }
                if !takeover.widgets.isEmpty {
                    VStack(spacing: NCPanelMetrics.rowGap * s) {
                        ForEach(takeover.widgets) { widget in WidgetView(widget: widget, takeover: takeover) }
                    }
                    .padding(.bottom, NCPanelMetrics.rowGap * s)
                }
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    if let title = section.title {
                        Heading(title: title, isFirst: index == 0 && takeover.widgets.isEmpty && !(o.appFilter && apps.count > 1)) {
                            RoundButton(symbol: "xmark") { takeover.clearAll(section) }
                        }
                    }
                    ForEach(section.groups) { group in GroupView(group: group, takeover: takeover) }
                }
                Footer(takeover: takeover, hasContent: !sections.isEmpty || !takeover.widgets.isEmpty)
            }
            .environment(\.panelScale, s)
            // The inset from the screen's edge on the panel's side, the close button's
            // room on the other.
            .padding([.top, .bottom], chrome)
            .padding(.leading, o.side == .left ? edge : chrome)
            .padding(.trailing, o.side == .right ? edge : chrome)
            .frame(width: CustomNCPanelController.width(o), alignment: .topLeading)
            .background(GeometryReader { g in
                Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
            })
        }
        .frame(width: CustomNCPanelController.width(o), height: listHeight)
    }

    /// A menu over the panel, with a layer under it that closes it on a click elsewhere in
    /// the panel, as a click outside a menu does. A click outside the panel closes
    /// Notification Center's, and ours with it.
    private func menuLayer(_ menu: NCPanelMenu, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .onTapGesture { takeover.dismissMenu() }
            PanelMenuView(menu: menu, takeover: takeover) { size in
                let bottom = menu.anchor.y + size.height + 8
                if abs(bottom - menuBottom) > 0.5 {
                    menuBottom = bottom
                    onHeight(min(max(contentHeight, bottom), maxHeight))
                }
            }
            .frame(width: menu.trailing ? max(menu.anchor.x, 1) : nil, alignment: .trailing)
            .offset(x: menu.trailing ? 0 : menu.anchor.x, y: menu.anchor.y)
        }
    }

    private var maxHeight: CGFloat { maxHeightOnScreen() }
    private var listHeight: CGFloat { max(min(contentHeight, maxHeight), 1) }
}

/// Rows by where they are in the panel's view, kept by the view, asked by the window when
/// it is right clicked.
@MainActor
final class NCPanelHitMap {
    var rowFrames: [String: CGRect] = [:]

    func row(at point: CGPoint) -> String? {
        rowFrames.first { $0.value.contains(point) }?.key
    }
}

/// Not part of the system's panel: a row of the apps listed, to show one at a time, only
/// when asked for in Settings. Glass pills like the system's own, with All first.
private struct AppFilterBar: View {
    let apps: [String]
    @Binding var filter: String?
    @Environment(\.panelScale) private var s
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6 * s) {
                chip(nil) { Text(loc.string("All")) }
                ForEach(apps, id: \.self) { app in
                    chip(app) {
                        HStack(spacing: 5 * s) {
                            AppIcon(appName: app, size: 14 * s)
                            Text(app).lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(height: NCPanelMetrics.footerHeight * s)
    }

    private func chip<Label: View>(_ app: String?, @ViewBuilder label: () -> Label) -> some View {
        let selected = filter == app
        let shape = Capsule()
        return Button { filter = app } label: {
            label()
                .font(.system(size: 11 * s, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10 * s)
                .frame(height: NCPanelMetrics.footerHeight * s)
                .background {
                    BannerGlass(shape: shape, cornerRadius: NCPanelMetrics.footerHeight * s / 2, scale: s)
                    if selected { shape.fill(Color.primary.opacity(0.18)) }
                }
                .panelBackdrop(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

/// The panel's way in and out: the banners' animations, applied to the whole list.
private struct PanelMotion: ViewModifier {
    let shown: Bool
    let animation: BannerAnimation
    let side: NCPanelSide

    func body(content: Content) -> some View {
        let t = shown ? BannerAnimation.Transform() : animation.hidden
        // Sideways motion comes from the panel's own edge: mirrored on the left, and in
        // the middle, where there is no edge, down from the top with a fade instead.
        var x = t.x, y = t.y, opacity = t.opacity
        switch side {
        case .right: break
        case .left: x = -t.x
        case .center:
            if t.x != 0 { y = -abs(t.x) * 0.5; x = 0; opacity = min(opacity, shown ? 1 : 0) }
        }
        let anchor: UnitPoint = side == .right ? .topTrailing : side == .left ? .topLeading : .top
        return content
            .opacity(opacity)
            .scaleEffect(t.scale, anchor: anchor)
            .rotationEffect(.degrees(side == .left ? -t.rotation : t.rotation))
            .offset(x: x, y: y)
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

/// The system's round glass button beside a heading and under the list: Clear, Clear All,
/// Clear Notifications.
private struct RoundButton: View {
    let symbol: String
    var size: CGFloat = NCPanelMetrics.roundButton
    let action: () -> Void
    @Environment(\.panelScale) private var s
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8 * s * size / NCPanelMetrics.roundButton, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: size * s, height: size * s)
                .background(BannerGlass(shape: Circle(), cornerRadius: size * s / 2, scale: s))
                .panelBackdrop(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A glass pill: Show Less beside an expanded stack's heading, Edit Widgets under the list.
private struct PillButton: View {
    let title: String
    var width: CGFloat = NCPanelMetrics.showLessWidth
    var height: CGFloat = NCPanelMetrics.roundButton
    let action: () -> Void
    @Environment(\.panelScale) private var s
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11 * s))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8 * s)
                .frame(minWidth: width * s)
                .frame(height: height * s)
                .background(BannerGlass(shape: Capsule(), cornerRadius: height * s / 2, scale: s))
                .panelBackdrop(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Under the list, as Notification Center has it: Edit Widgets, and while there is
/// something to clear, the ✕ with Clear Banners Only and Clear All Notifications. With no
/// notifications and no widgets it is all the panel shows, as on the system's.
private struct Footer: View {
    @ObservedObject var takeover: NCPanelTakeover
    let hasContent: Bool
    @Environment(\.panelScale) private var s
    @State private var clearFrame: CGRect = .zero

    var body: some View {
        let footer = takeover.footer
        if footer.editWidgets != nil || footer.clear != nil {
            HStack(spacing: NCPanelMetrics.footerGap * s) {
                if let edit = footer.editWidgets {
                    PillButton(title: edit, width: NCPanelMetrics.editWidgetsWidth, height: NCPanelMetrics.footerHeight) {
                        takeover.editWidgets()
                    }
                }
                if let clear = footer.clear {
                    RoundButton(symbol: "xmark", size: NCPanelMetrics.footerHeight) {
                        takeover.showClearMenu(at: CGPoint(x: clearFrame.minX, y: clearFrame.maxY + 4 * s))
                    }
                    .help(clear)
                    .accessibilityLabel(clear)
                    .modifier(PanelFrameReader(frame: $clearFrame))
                }
            }
            .frame(width: CustomNCPanelController.rowWidth * s)
            // The rows end in their gap already.
            .padding(.top, hasContent ? (NCPanelMetrics.footerAbove - NCPanelMetrics.rowGap) * s : 0)
        }
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
    @State private var frame: CGRect = .zero
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
        let shape = RoundedRectangle(cornerRadius: CustomBannerView.Metrics.cornerRadius * s, style: .continuous)
        BannerCard(content: content, scale: s, tint: takeover.tint(row.appName), textColor: options.textColor,
                   redactContent: options.redact, hovered: hovering, edge: .panelRow,
                   onOpen: { takeover.activate(row) },
                   onAction: { takeover.perform($0, on: row) },
                   onDetails: { takeover.toggleDetails(row) },
                   // The system's menu hangs from under the ⋯, its right edge past the row's.
                   onMore: { more in
                       takeover.showMenu(for: row, withAppActions: false,
                                         at: CGPoint(x: frame.minX + more.maxX + 40 * s, y: frame.minY + more.maxY + 6 * s),
                                         trailing: true)
                   },
                   onOptions: { pill in
                       takeover.showOptions(for: row, at: CGPoint(x: frame.minX + pill.maxX, y: frame.minY + pill.maxY + 4 * s))
                   })
            .frame(width: CustomNCPanelController.rowWidth * s, height: row.height * s)
            // Notification Center animates a row growing for its buttons or a reply, and
            // its height is read a few times on the way: ours glides between them rather
            // than jumping at each.
            .animation(.smooth(duration: 0.22), value: row.height)
            .animation(.smooth(duration: 0.22), value: row.expanded)
            .panelBackdrop(shape)
            .overlay(alignment: .topTrailing) {
                // Notification Center's own time, where it draws it; the hover controls take
                // its place, as on the system's.
                if !hovering, !row.expanded, let time = row.time {
                    Text(time)
                        .font(.system(size: 11 * s).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 13 * s).padding(.trailing, 14 * s)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if hovering {
                    CloseButton { takeover.close(row) }
                        .offset(x: CustomBannerView.Metrics.closeOrigin.x * s, y: CustomBannerView.Metrics.closeOrigin.y * s)
                }
            }
            .modifier(PanelFrameReader(frame: $frame))
            .background(GeometryReader { g in
                Color.clear.preference(key: RowFramesKey.self, value: [row.id: g.frame(in: .named(NCPanelSpace.name))])
            })
            .activeHover { inside in withAnimation(.easeInOut(duration: 0.15)) { hovering = inside } }
    }
}

/// A menu of Notification Center's, drawn in our panel as the system draws its menus:
/// glass, 24 point items, short separators, a section's name in small bold gray, the item
/// under the pointer in the accent colour (sizes from the real menu's frames, scripts/
/// panel-lab `real-hover`).
private struct PanelMenuView: View {
    let menu: NCPanelMenu
    @ObservedObject var takeover: NCPanelTakeover
    let onSize: (CGSize) -> Void

    private static let itemHeight: CGFloat = 24
    private static let separatorHeight: CGFloat = 11
    private static let padding: CGFloat = 5
    private static let radius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(menu.items) { item in
                switch item.kind {
                case .separator:
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                        .padding(.horizontal, 10)
                        .frame(height: Self.separatorHeight)
                case .header:
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: Self.itemHeight, alignment: .leading)
                case .action:
                    MenuItemRow(title: item.title) { takeover.choose(item) }
                }
            }
        }
        .padding(.vertical, Self.padding)
        .frame(minWidth: 160, alignment: .leading)
        .fixedSize()
        .background {
            BannerGlass(shape: shape, cornerRadius: Self.radius)
            shape.fill(Color.black.opacity(0.12))
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { onSize(g.size) }
                .onChange(of: g.size) { _, size in onSize(size) }
        })
    }
}

private struct MenuItemRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(hovering ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .padding(.leading, 9).padding(.trailing, 24)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .background {
                    if hovering {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .controlAccentColor))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .activeHover { hovering = $0 }
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
            .panelBackdrop(shape)
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
                .panelBackdrop(Circle())
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
