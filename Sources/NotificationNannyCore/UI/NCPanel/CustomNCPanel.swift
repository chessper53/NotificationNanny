import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Never take key or main status: stealing focus closes the native panel.
/// PanelClickRouter delivers clicks directly, so the hosting view must accept the first click.
final class NCPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accept the initial click even while the window is inactive.
package class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override package func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FirstMouseHostingView<Content: View>: FirstClickHostingView<Content> {
    /// A right click, at its place in the view (top left origin).
    var onRightClick: ((CGPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
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

    /// Native column dimensions measured on macOS 27, in points.
    static let rowWidth: CGFloat = 344
    static let rightInset: CGFloat = 16
    static let topInset: CGFloat = 46
    /// Room around the rows for what overhangs them: a row's close button.
    static let chrome: CGFloat = CustomBannerView.Metrics.chromeInset
    /// Scale rows and close button margins, but retain the native screen edge inset.
    static func width(_ o: NCPanelOptions) -> CGFloat {
        // In the middle there is no edge to reach, only the close button's room each side.
        o.side == .center ? (chrome * 2 + rowWidth) * o.scale : (chrome + rowWidth) * o.scale + rightInset
    }

    /// Row bounds in AppKit coordinates, leaving room for the screen inset and close button.
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

    /// Clamp offsets for the current screen, retaining the native edge inset on both sides.
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

    let presentation = PanelPresentation()

    init(takeover: NCPanelTakeover) {
        self.takeover = takeover
        window = NCPanelWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width(NCPanelOptions()), height: 120),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        // Native rows cast no panel shadow.
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Override appearance in lab runs without changing the system setting.
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
        // The controller owns window size; content must not resize it.
        host.sizingOptions = []
        host.onRightClick = { [weak takeover] point in
            if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" {
                FileHandle.standardError.write(Data("[panel view] right click at \(point) → \(hitMap.row(at: point) ?? "nothing"), \(hitMap.rowFrames.count) frames\n".utf8))
            }
            guard let takeover, let id = hitMap.row(at: point) else { return }
            if id.hasPrefix(NCPanelHitMap.widgetPrefix) {
                let widgetID = String(id.dropFirst(NCPanelHitMap.widgetPrefix.count))
                if let widget = takeover.widgets.first(where: { $0.id == widgetID }) {
                    takeover.showMenu(for: widget, at: point)
                }
                return
            }
            guard let row = takeover.snapshot.sections.lazy.flatMap({ $0.groups }).flatMap({ $0.rows }).first(where: { $0.id == id })
            else { return }
            takeover.showMenu(for: row, withAppActions: true, at: point, trailing: false)
        }
        window.contentView = host
        if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" {
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak window] event in
                FileHandle.standardError.write(Data("[app] scroll \(event.scrollingDeltaY) to window \(event.windowNumber), panel \(window?.windowNumber ?? -1)\n".utf8))
                return event
            }
        }
    }

    func show(on screen: NSScreen) {
        self.screen = screen
        layout()
        window.alphaValue = 1
        window.orderFrontRegardless()
        if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" {
            FileHandle.standardError.write(Data("[panel window] shown uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
        }
        // Start outside, then animate inward on the next pass.
        presentation.shown = false
        DispatchQueue.main.async { [presentation] in presentation.shown = true }
    }

    func hide(after outro: Double) {
        guard window.isVisible else { return }
        presentation.shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + outro + 0.05) { [weak self] in
            guard let self, !self.presentation.shown else { return }
            self.window.orderOut(nil)
        }
    }

    var maxHeight: CGFloat {
        guard let screen else { return 600 }
        return screen.frame.height - Self.topInset - options.topOffset - Self.rightInset + Self.chrome * options.scale * 2
    }

    func relayout() { layout() }

    private func contentHeightChanged(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        layout()
    }

    /// Fit content exactly: the click router would otherwise swallow clicks in transparent margins.
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
        if ProcessInfo.processInfo.environment["NN_TIMING"] == "1" {
            FileHandle.standardError.write(Data("[panel window] height \(Int(height)) uptime \(ProcessInfo.processInfo.systemUptime)\n".utf8))
        }
    }
}

@MainActor
final class PanelPresentation: ObservableObject {
    @Published var shown = false
}

// MARK: View

/// Panel scale relative to native size; apply it to every measurement.
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

/// Row bounds used to route secondary clicks.
private struct RowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Panel content coordinates with a top left origin for menus and secondary clicks.
enum NCPanelSpace {
    static let name = "ncPanel"
}

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

/// Native list geometry measured on macOS 27.
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
    /// Native footer button dimensions and spacing, in points.
    static let footerAbove: CGFloat = 16
    /// From the last notification to the first widget under them.
    static let widgetsAbove: CGFloat = 16
    static let footerHeight: CGFloat = 24
    static let footerGap: CGFloat = 8
    static let editWidgetsWidth: CGFloat = 87
    /// Darken beneath glass by 21% to match the native panel.
    /// Apply only under rows and buttons to avoid a visible rectangular backdrop.
    static let behindGlass: Double = 0.21
    static let stackLayerDim: Double = 0.09
}

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
    /// Use the controller's available height so the list and window clamp identically.
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
        // Pin to the top while the controller's window size and the view's content height catch up.
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
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    if let title = section.title {
                        Heading(title: title, isFirst: index == 0 && !(o.appFilter && apps.count > 1)) {
                            RoundButton(symbol: "xmark") { takeover.clearAll(section) }
                        }
                    }
                    ForEach(section.groups) { group in GroupView(group: group, takeover: takeover) }
                }
                // Keep the native 16 point widget gap; notification rows already include their own
                // trailing gap.
                if !takeover.widgets.isEmpty {
                    VStack(spacing: NCPanelMetrics.rowGap * s) {
                        ForEach(takeover.widgets) { widget in WidgetView(widget: widget, takeover: takeover) }
                    }
                    .padding(.top, sections.isEmpty ? 0 : (NCPanelMetrics.widgetsAbove - NCPanelMetrics.rowGap) * s)
                    .padding(.bottom, NCPanelMetrics.rowGap * s)
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
        // An almost transparent fill keeps scrolls in the row gaps from reaching windows behind the
        // panel.
        .background(Color.black.opacity(0.005))
    }

    /// Draw the menu over a dismiss layer; clicks outside the panel close the native panel too.
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

/// Maps panel frames to row and widget identifiers for secondary clicks.
@MainActor
final class NCPanelHitMap {
    /// Rows by their ID, widgets by this and theirs.
    static let widgetPrefix = "widget:"
    var rowFrames: [String: CGRect] = [:]

    func row(at point: CGPoint) -> String? {
        rowFrames.first { $0.value.contains(point) }?.key
    }
}

/// Optional app filter using glass pills, with All first.
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

/// Apply the chosen banner animation to the entire panel.
private struct PanelMotion: ViewModifier {
    let shown: Bool
    let animation: BannerAnimation
    let side: NCPanelSide

    func body(content: Content) -> some View {
        let t = shown ? BannerAnimation.Transform() : animation.hidden
        // Mirror motion at the left edge; centered panels enter from above with a fade.
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

/// Native heading with buttons on the right.
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

/// Native footer actions, also shown when the list and widget area are empty.
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
                if row.isStack {
                    // Part of the stack: a click on them expands it, as on the system's.
                    StackEdges(tint: takeover.tint(row.appName))
                        .contentShape(Rectangle())
                        .onTapGesture { takeover.activate(row) }
                        .padding(.top, -NCPanelMetrics.rowGap * s)
                }
            }
        }
        .padding(.bottom, (NCPanelMetrics.rowGap + (group.expanded ? NCPanelMetrics.stackPeek : 0)) * s)
    }
}

/// Share BannerCard appearance and interaction with custom banners.
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
        c.time = row.time
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
                   // Anchor the native style menu under the more button, extending beyond the row.
                   onMore: { more in
                       takeover.showMenu(for: row, withAppActions: false,
                                         at: CGPoint(x: frame.minX + more.maxX + 40 * s, y: frame.minY + more.maxY + 6 * s),
                                         trailing: true)
                   },
                   onOptions: { pill in
                       takeover.showOptions(for: row, at: CGPoint(x: frame.minX + pill.maxX, y: frame.minY + pill.maxY + 4 * s))
                   })
            .frame(width: CustomNCPanelController.rowWidth * s, height: row.height * s)
            // Smoothly follow native row height changes while details or replies animate.
            .animation(.smooth(duration: 0.22), value: row.height)
            .animation(.smooth(duration: 0.22), value: row.expanded)
            // Clip animated content so a changing row never draws over its neighbour.
            .clipShape(shape)
            .panelBackdrop(shape)
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

/// Native menu appearance: glass, 24 point actions, short separators, and small section headings.
private struct PanelMenuView: View {
    let menu: NCPanelMenu
    @ObservedObject var takeover: NCPanelTakeover
    let onSize: (CGSize) -> Void

    private static let itemHeight: CGFloat = 24
    private static let separatorHeight: CGFloat = 11
    private static let padding: CGFloat = 5
    private static let radius: CGFloat = 10
    /// The room a tick takes before an item's title.
    static let tickWidth: CGFloat = 14

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
                        // Over its items' titles, past the ticks.
                        .padding(.leading, menu.items.contains(where: \.checked) ? Self.tickWidth : 0)
                        .frame(height: Self.itemHeight, alignment: .leading)
                case .action:
                    MenuItemRow(title: item.title, checked: item.checked,
                                ticks: menu.items.contains(where: \.checked)) { takeover.choose(item) }
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
    /// Align every title with the checkmark column whenever any item is checked.
    var checked = false
    var ticks = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if ticks {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(checked ? 1 : 0)
                        .frame(width: PanelMenuView.tickWidth, alignment: .leading)
                }
                Text(title).lineLimit(1)
            }
                .font(.system(size: 13))
                .foregroundStyle(hovering ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
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

/// Draw each collapsed card's exposed strip only; overlapping glass would brighten it twice.
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
        // Reduce brightness 9% to compensate for the card above showing through the thin glass.
        return BannerGlass(shape: shape, cornerRadius: radius, scale: s, tint: tint)
            .overlay(shape.fill(Color.black.opacity(NCPanelMetrics.stackLayerDim)))
            .panelBackdrop(shape)
            .frame(height: 40 * s)
            .padding(.horizontal, inset)
            .frame(height: NCPanelMetrics.stackPeek / 2 * s, alignment: .bottom)
            .clipped()
    }
}

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

/// Native widget capture; forward clicks at the corresponding position on the real widget.
private struct WidgetView: View {
    let widget: NCWidget
    @ObservedObject var takeover: NCPanelTakeover

    @Environment(\.panelScale) private var s

    /// Measured native corner radius; smaller masks expose the capture's black corners.
    static let cornerRadius: CGFloat = 28

    var body: some View {
        // Keep the previous image and size until a new capture arrives; use a placeholder only
        // before the first capture.
        let shown = widget.image?.size ?? widget.frameInWindow.size
        let size = CGSize(width: shown.width * s, height: shown.height * s)
        Group {
            if let image = widget.image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: Self.cornerRadius * s, style: .circular).fill(Color.primary.opacity(0.06))
            }
        }
        .frame(width: size.width, height: size.height)
        // The capture's corners hold whatever was behind the widget's rounded ones, black.
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius * s, style: .circular))
        .contentShape(Rectangle())
        .background(GeometryReader { g in
            Color.clear.preference(key: RowFramesKey.self,
                                   value: [NCPanelHitMap.widgetPrefix + widget.id: g.frame(in: .named(NCPanelSpace.name))])
        })
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
        Image(nsImage: AppIconCache.shared.icon(for: appName) ?? NSWorkspace.shared.icon(for: .applicationBundle))
            .resizable().interpolation(.high).frame(width: size, height: size)
    }
}
