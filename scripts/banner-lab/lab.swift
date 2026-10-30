// Banner lab: measures the custom banner against the real Notification Center
// banner, pixel for pixel. Run it through run.sh, which builds it.
//
// It puts a window with a known backdrop (solid colours, stripes, a checker)
// where the system banner appears, then captures either the real banner or our
// replica in exactly that spot. score.py diffs the two. Everything is saved per
// appearance, so Dark and Light Mode are compared separately.
//
//   lab real  <backdrop...>                      real banner via osascript
//   lab prod  <name> [key=value...] -- <backdrop...>
//                                                the app's own CustomBannerView
//                                                (only in the build that links
//                                                CustomOverlay.swift)
//   lab cand  <name> [key=value...] -- <backdrop...>
//                                                a bare AppKit mock-up, for
//                                                trying parameters quickly
//   lab theme light|dark                         switch system appearance
//   lab real-states <backdrop>                   a Lab notification with buttons, from
//                                                notify-lab, in every state: collapsed,
//                                                hovered, details shown, reply open,
//                                                reply typed; frames to states.txt
//   lab prod-states <backdrop>                   the app's BannerCard in the same states,
//                                                at the real ones' frames
//
// Backdrops: black white gray red blue stripes checker wallpaper (no backdrop)
//
// Needs Accessibility (to find the banner) and Screen Recording (to capture it)
// for whichever app runs it. Quit NotificationNanny first, or at least keep its
// banner animation on Default, so the real banner is not replaced by ours.
import AppKit
import ApplicationServices

let outDir = ProcessInfo.processInfo.environment["BANNER_LAB_OUT"] ?? "build/banner-lab"
let margin: CGFloat = 30
let backdropPad: CGFloat = 90

// MARK: helpers

func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}

func axFrame(_ e: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(e, "AXPosition") { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(e, "AXSize") { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}

func findBanner(_ e: AXUIElement) -> AXUIElement? {
    if (attr(e, "AXSubrole") as? String) == "AXNotificationCenterBanner" { return e }
    for k in (attr(e, "AXChildren") as? [AXUIElement] ?? []) { if let f = findBanner(k) { return f } }
    return nil
}

func currentBanner() -> AXUIElement? {
    guard let nc = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return nil }
    let app = AXUIElementCreateApplication(nc.processIdentifier)
    for w in (attr(app, "AXWindows") as? [AXUIElement] ?? []) { if let b = findBanner(w) { return b } }
    return nil
}

let primaryHeight = NSScreen.screens[0].frame.height
func nsRect(_ ax: CGRect) -> NSRect {
    NSRect(x: ax.minX, y: primaryHeight - ax.maxY, width: ax.width, height: ax.height)
}

func run(_ path: String, _ args: [String]) {
    let t = Process()
    t.executableURL = URL(fileURLWithPath: path)
    t.arguments = args
    try? t.run()
    t.waitUntilExit()
}

func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

var appearanceName: String {
    NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
}

func capture(_ ax: CGRect, _ name: String) {
    let r = ax.insetBy(dx: -margin, dy: -margin)
    run("/usr/sbin/screencapture",
        ["-x", "-R\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))",
         "\(outDir)/cap/\(appearanceName)/\(name).png"])
}

/// `key=value` pairs up to `--`, then the backdrops after it.
func parse(_ args: ArraySlice<String>) -> ([String: String], [String]) {
    let sep = args.firstIndex(of: "--") ?? args.endIndex
    var p: [String: String] = [:]
    for kv in args[args.startIndex..<sep] {
        let s = kv.split(separator: "=", maxSplits: 1)
        p[String(s[0])] = s.count > 1 ? String(s[1]) : ""
    }
    let backdrops = sep < args.endIndex ? Array(args[(sep + 1)...]) : []
    return (p, backdrops)
}

func param(_ p: [String: String], _ k: String, _ d: Double) -> CGFloat { CGFloat(Double(p[k] ?? "") ?? d) }

func color(_ s: String?) -> NSColor? {
    guard let s, !s.isEmpty, s != "none" else { return nil }
    let c = s.split(separator: ",").map { CGFloat(Double($0)!) }
    return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c.count > 3 ? c[3] : 1)
}

// MARK: backdrops

final class PatternView: NSView {
    let kind: String
    init(frame: NSRect, kind: String) { self.kind = kind; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        func fill(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
            NSColor(srgbRed: r, green: g, blue: b, alpha: 1).setFill(); bounds.fill()
        }
        switch kind {
        case "black": fill(0, 0, 0)
        case "white": fill(1, 1, 1)
        case "gray":  fill(0.5, 0.5, 0.5)
        case "red":   fill(0.9, 0.1, 0.1)
        case "blue":  fill(0.1, 0.2, 0.9)
        case "stripes":
            // 20pt bars: shows how far the glass blurs and where it refracts.
            fill(1, 1, 1)
            NSColor.black.setFill()
            var x: CGFloat = 0
            while x < bounds.width { NSRect(x: x, y: 0, width: 20, height: bounds.height).fill(); x += 40 }
        case "checker":
            let a = NSColor(srgbRed: 0.95, green: 0.8, blue: 0.2, alpha: 1)
            let b = NSColor(srgbRed: 0.1, green: 0.5, blue: 0.4, alpha: 1)
            for i in 0...Int(bounds.width / 24) {
                for j in 0...Int(bounds.height / 24) {
                    ((i + j) % 2 == 0 ? a : b).setFill()
                    NSRect(x: CGFloat(i) * 24, y: CGFloat(j) * 24, width: 24, height: 24).fill()
                }
            }
        default: break
        }
    }
}

var backdropWindow: NSWindow?
func showBackdrop(_ kind: String, around ax: CGRect) {
    backdropWindow?.orderOut(nil)
    backdropWindow = nil
    guard kind != "wallpaper" else { return }
    let f = nsRect(ax.insetBy(dx: -backdropPad, dy: -backdropPad))
    let w = NSWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .floating
    w.hasShadow = false
    w.contentView = PatternView(frame: NSRect(origin: .zero, size: f.size), kind: kind)
    w.orderFrontRegardless()
    backdropWindow = w
}

// MARK: real banner

func waitForBanner(present: Bool, timeout: Double) -> AXUIElement? {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        let b = currentBanner()
        if present, b != nil { return b }
        if !present, b == nil { return nil }
        pump(0.1)
    }
    return nil
}

/// Where the real banner last appeared. Replicas are drawn at the same spot.
var frameURL: URL { URL(fileURLWithPath: "\(outDir)/frame.txt") }
func loadFrame() -> CGRect {
    guard let s = try? String(contentsOf: frameURL, encoding: .utf8) else {
        print("No banner frame yet. Run `real` first."); exit(1)
    }
    let v = s.split(separator: " ").map { CGFloat(Double($0)!) }
    return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
}

// MARK: AppKit mock-up (cand)

func roundedMask(_ radius: CGFloat) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
}

final class Flipped: NSView { override var isFlipped: Bool { true } }

let probeIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Script Editor.app")

func mockContent(_ size: CGSize, _ p: [String: String]) -> NSView {
    let v = Flipped(frame: NSRect(origin: .zero, size: size))
    let iconSize = param(p, "icon", 38), iconX = param(p, "iconX", 10)
    let iv = NSImageView(frame: NSRect(x: iconX, y: (size.height - iconSize) / 2, width: iconSize, height: iconSize))
    iv.image = probeIcon
    iv.imageScaling = .scaleProportionallyUpOrDown
    v.addSubview(iv)
    func label(_ s: String, y: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: param(p, "fontSize", 13), weight: weight)
        l.textColor = (color(p["textColor"]) ?? .white).withAlphaComponent(param(p, "textAlpha", 0.85))
        l.sizeToFit()
        // NSTextField insets its text by 2pt, so 56 puts the glyphs at 58.
        l.frame.origin = CGPoint(x: param(p, "textX", 56), y: y)
        return l
    }
    v.addSubview(label("Probe title", y: 12, weight: .semibold))
    v.addSubview(label("Probe body text", y: 29, weight: .regular))
    return v
}

func mockBanner(_ size: CGSize, _ p: [String: String]) -> NSView {
    let radius = param(p, "radius", 20)
    let content = mockContent(size, p)
    if let w = p["wash"] {
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 1, alpha: param(p, "wash", Double(w) ?? 0)).cgColor
        content.layer?.cornerRadius = radius
        content.layer?.cornerCurve = .continuous
    }
    if let material = p["material"] {
        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        let all: [String: NSVisualEffectView.Material] = [
            "hudWindow": .hudWindow, "popover": .popover, "menu": .menu, "sheet": .sheet,
            "sidebar": .sidebar, "headerView": .headerView, "windowBackground": .windowBackground,
            "underWindowBackground": .underWindowBackground, "fullScreenUI": .fullScreenUI, "toolTip": .toolTip]
        fx.material = all[material] ?? .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.maskImage = roundedMask(radius)
        fx.addSubview(content)
        return fx
    }
    let g = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
    g.cornerRadius = radius
    g.style = p["style"] == "clear" ? .clear : .regular
    g.tintColor = color(p["tint"])
    // Private, for comparison only. None of these beat the public .regular.
    if let v = p["variant"] { g.setValue(Int(v)!, forKey: "_variant") }
    g.contentView = content
    return g
}

// MARK: main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let args = Array(CommandLine.arguments.dropFirst())
try? FileManager.default.createDirectory(atPath: "\(outDir)/cap/\(appearanceName)",
                                         withIntermediateDirectories: true)

switch args.first {
case "real-states":
    // Every state of a real banner with buttons, posted by a notify-lab app. Only Lab
    // notifications are acted on, and typing happens only once the reply field has focus.
    let bd = args.dropFirst().first ?? "gray"
    let notifier = "build/notify-lab/Lab Charlie.app/Contents/MacOS/notifier"
    func labBanner() -> AXUIElement? {
        guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return nil }
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        func walk(_ e: AXUIElement, _ d: Int) -> AXUIElement? {
            guard d < 12 else { return nil }
            if let sub = attr(e, "AXSubrole") as? String, sub.hasPrefix("AXNotificationCenter"),
               let desc = attr(e, "AXAttributedDescription"), CFGetTypeID(desc) == CFAttributedStringGetTypeID(),
               (CFAttributedStringGetString((desc as! CFAttributedString)) as String).hasPrefix("Lab Charlie") { return e }
            for k in (attr(e, "AXChildren") as? [AXUIElement] ?? []) { if let f = walk(k, d + 1) { return f } }
            return nil
        }
        for w in (attr(app, "AXWindows") as? [AXUIElement] ?? []) { if let b = walk(w, 0) { return b } }
        return nil
    }
    func act(_ e: AXUIElement, _ name: String) {
        var ref: CFArray?
        AXUIElementCopyActionNames(e, &ref)
        if let a = (ref as? [String] ?? []).first(where: { $0.hasPrefix("Name:\(name)\n") }) {
            AXUIElementPerformAction(e, a as CFString)
        }
    }
    run(notifier, ["Probe title", "Probe body text", "--actions"])
    var end = Date().addingTimeInterval(8)
    var banner: AXUIElement?
    while banner == nil, Date() < end { banner = labBanner(); pump(0.1) }
    guard let banner else { print("no Lab banner"); exit(1) }
    pump(1.0)
    var states: [String] = []
    let tall = axFrame(banner).insetBy(dx: 0, dy: 0)
    showBackdrop(bd, around: CGRect(x: tall.minX, y: tall.minY, width: tall.width, height: 200))
    pump(0.6)
    func snap(_ state: String) {
        let f = axFrame(banner)
        states.append("\(state) \(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height))")
        capture(f, "real-state-\(state)-\(bd)")
    }
    snap("collapsed")
    let back = CGEvent(source: nil)!.location
    let f0 = axFrame(banner)
    // From the left: a pointer arriving from below was at times not taken as entering it.
    for p in [CGPoint(x: f0.minX - 400, y: f0.minY + 200), CGPoint(x: f0.minX - 20, y: f0.midY), CGPoint(x: f0.midX, y: f0.midY)] {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
        pump(0.3)
    }
    pump(0.6)
    snap("hover")
    // What the hovered banner shows, relative to its card.
    let card = f0
    func dump(_ e: AXUIElement, _ d: Int) {
        guard d < 6 else { return }
        let f = axFrame(e)
        let role = attr(e, "AXRole") as? String ?? "?"
        let id = attr(e, "AXIdentifier") as? String ?? ""
        let desc = (attr(e, "AXDescription") as? String) ?? (attr(e, "AXTitle") as? String) ?? ""
        if d > 0 { print("  hover: \(role) #\(id) \"\(desc)\" at (\(Int(f.minX - card.minX)),\(Int(f.minY - card.minY))) \(Int(f.width))x\(Int(f.height))") }
        for k in (attr(e, "AXChildren") as? [AXUIElement] ?? []) { dump(k, d + 1) }
    }
    dump(banner, 0)
    // At the top left corner, where the frame grows on hover: a close button?
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: f0.minX + 6, y: f0.minY + 6), mouseButton: .left)!.post(tap: .cghidEventTap)
    pump(0.8)
    snap("corner")
    // Away, so the rest is as it looks without the pointer on it.
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)!.post(tap: .cghidEventTap)
    pump(0.6)
    act(banner, "Show Details")
    pump(1.0)
    snap("expanded")
    act(banner, "Reply")
    pump(1.0)
    snap("reply")
    func field(_ e: AXUIElement, _ d: Int) -> AXUIElement? {
        guard d < 8 else { return nil }
        if let r = attr(e, "AXRole") as? String, r == "AXTextArea" || r == "AXTextField" { return e }
        for k in (attr(e, "AXChildren") as? [AXUIElement] ?? []) { if let f = field(k, d + 1) { return f } }
        return nil
    }
    if let f = field(banner, 0) {
        AXUIElementSetAttributeValue(f, "AXFocused" as CFString, kCFBooleanTrue)
        pump(0.4)
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), "AXFocusedUIElement" as CFString, &focused)
        if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID(), CFEqual(focused, f) {
            for ch in "Hello there".utf16 {
                var c = ch
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
                    e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
                    e.post(tap: .cghidEventTap)
                }
                usleep(15_000)
            }
            pump(0.6)
            snap("typed")
        } else {
            print("reply field not focused; not typing")
        }
    }
    act(banner, "Close")
    backdropWindow?.orderOut(nil)
    try? states.joined(separator: "\n").write(toFile: "\(outDir)/states.txt", atomically: true, encoding: .utf8)
    print(states.joined(separator: "\n"))

#if PROD
case "prod-states":
    // The app's own card in each state the real one was captured in, at its frame.
    let bd = args.dropFirst().first ?? "gray"
    guard let text = try? String(contentsOfFile: "\(outDir)/states.txt", encoding: .utf8) else { print("run real-states first"); exit(1) }
    let base = BannerContent(appName: "Script Editor", title: "Probe title", body: "Probe body text", appIcon: probeIcon,
                             actions: ["Reply", "Archive", "Snooze"])
    let manager = MainActor.assumeIsolated { CustomBannerManager() }
    var first = true
    var collapsed: CGRect?
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: " ")
        guard parts.count == 5, let x = Double(parts[1]), let y = Double(parts[2]),
              let w = Double(parts[3]), let h = Double(parts[4]) else { continue }
        let state = String(parts[0])
        let shot = CGRect(x: x, y: y, width: w, height: h)
        var ax = shot
        if state == "collapsed" { collapsed = ax }
        // A hovered banner's frame takes in its close button, which overhangs the card.
        if state == "hover" || state == "corner", let c = collapsed { ax = c }
        var content = base
        switch state {
        case "expanded": content.expanded = true
        case "reply": content.expanded = true; content.reply = ""; content.replyPlaceholder = "Message"
                      content.actions = ["Send", "Archive", "Snooze"]
        case "typed": content.expanded = true; content.reply = "Hello there"; content.replyPlaceholder = "Message"
                      content.actions = ["Send", "Archive", "Snooze"]
        default: break
        }
        if state == "hover" { setenv("NN_LOOK_HOVER", "1", 1) } else { unsetenv("NN_LOOK_HOVER") }
        showBackdrop(bd, around: CGRect(x: ax.minX, y: ax.minY, width: ax.width, height: 200))
        pump(first ? 1.2 : 0.6)
        first = false
        MainActor.assumeIsolated {
            manager.showBanner(content: content, axTopLeft: ax.origin, width: ax.width, height: ax.height,
                               scale: 1, backgroundColor: .clear, autoDismissSeconds: 0,
                               animation: .fade, onOpen: {}, key: 1)
        }
        pump(0.9)
        capture(shot, "ours-state-\(state)-\(bd)")
        MainActor.assumeIsolated { manager.dismiss(key: 1) }
        pump(0.5)
    }
    backdropWindow?.orderOut(nil)
#endif

case "corner-sweep":
    // Where must the pointer be for the real banner's close button to show? A Lab
    // notification, then the pointer at points measured from its top left corner.
    let notifier = "build/notify-lab/Lab Charlie.app/Contents/MacOS/notifier"
    run(notifier, ["Probe title", "Probe body text"])
    var b: AXUIElement?
    let end = Date().addingTimeInterval(8)
    while b == nil, Date() < end {
        if let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first {
            func walk(_ e: AXUIElement, _ d: Int) -> AXUIElement? {
                guard d < 12 else { return nil }
                if let sub = attr(e, "AXSubrole") as? String, sub.hasPrefix("AXNotificationCenter"),
                   let desc = attr(e, "AXAttributedDescription"), CFGetTypeID(desc) == CFAttributedStringGetTypeID(),
                   (CFAttributedStringGetString((desc as! CFAttributedString)) as String).hasPrefix("Lab Charlie") { return e }
                for k in (attr(e, "AXChildren") as? [AXUIElement] ?? []) { if let f = walk(k, d + 1) { return f } }
                return nil
            }
            for w in (attr(AXUIElementCreateApplication(nc.processIdentifier), "AXWindows") as? [AXUIElement] ?? []) {
                if let f = walk(w, 0) { b = f; break }
            }
        }
        pump(0.1)
    }
    guard let banner = b else { print("no Lab banner"); exit(1) }
    pump(1.0)
    let card = axFrame(banner)
    let back = CGEvent(source: nil)!.location
    // Where the close button's ring sits, from the corner capture.
    let spot = CGRect(x: card.minX - 8, y: card.minY - 5, width: 22, height: 22)
    func grab(_ name: String) -> NSBitmapImageRep? {
        run("/usr/sbin/screencapture", ["-x", "-R\(Int(spot.minX)),\(Int(spot.minY)),\(Int(spot.width)),\(Int(spot.height))", "\(outDir)/\(name).png"])
        defer { try? FileManager.default.removeItem(atPath: "\(outDir)/\(name).png") }
        return NSImage(contentsOfFile: "\(outDir)/\(name).png").flatMap { $0.tiffRepresentation }.flatMap(NSBitmapImageRep.init)
    }
    func move(_ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    }
    move(CGPoint(x: card.midX, y: card.maxY + 80)); pump(0.6)
    guard let base = grab("sweep-base") else { exit(1) }
    func differs(_ r: NSBitmapImageRep) -> Double {
        var total = 0.0, n = 0.0
        for x in stride(from: 0, to: min(r.pixelsWide, base.pixelsWide), by: 1) {
            for y in stride(from: 0, to: min(r.pixelsHigh, base.pixelsHigh), by: 1) {
                guard let a = r.colorAt(x: x, y: y), let c = base.colorAt(x: x, y: y) else { continue }
                total += abs(a.brightnessComponent - c.brightnessComponent); n += 1
            }
        }
        return n > 0 ? total / n * 255 : 0
    }
    // Over time: the middle first, then well away, then the corner.
    for (label, dx, dy) in [("x80", 80, 29), ("x110", 110, 29), ("x140", 140, 29), ("x160", 160, 29),
                            ("x172", 172, 29), ("x200", 200, 29), ("x260", 260, 29), ("x330", 330, 29), ("x172y8", 172, 8), ("x172y52", 172, 52)] {
        move(CGPoint(x: card.minX - 400, y: card.minY + 200)); pump(0.5)
        move(CGPoint(x: card.minX + CGFloat(dx), y: card.minY + CGFloat(dy)))
        var line = "\(label):"
        let t0 = Date()
        for t in [0.4] {
            pump(t - Date().timeIntervalSince(t0))
            if let r = grab("sweep") { line += String(format: "  %.1fs %.1f", t, differs(r)) }
        }
        print(line)
    }
    move(back)
    var ref: CFArray?
    AXUIElementCopyActionNames(banner, &ref)
    if let a = (ref as? [String] ?? []).first(where: { $0.hasPrefix("Name:Close\n") }) { AXUIElementPerformAction(banner, a as CFString) }

case "theme":
    // SkyLight rather than System Events, so no Automation permission is needed.
    let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    typealias SetTheme = @convention(c) (Bool) -> Void
    guard let sym = dlsym(sky, "SLSSetAppearanceThemeLegacy") else { print("SkyLight call not found"); exit(1) }
    unsafeBitCast(sym, to: SetTheme.self)(args.dropFirst().first == "dark")

case "real":
    for bd in args.dropFirst() {
        _ = waitForBanner(present: false, timeout: 12)
        var ax = (try? String(contentsOf: frameURL, encoding: .utf8)) != nil
            ? loadFrame() : CGRect(x: NSScreen.screens[0].frame.maxX - 360, y: 40, width: 344, height: 58)
        showBackdrop(bd, around: ax)
        pump(0.4)
        run("/usr/bin/osascript", ["-e", "display notification \"Probe body text\" with title \"Probe title\""])
        guard let b = waitForBanner(present: true, timeout: 5) else { print("no banner for \(bd)"); continue }
        pump(1.4) // let the intro animation settle
        let found = axFrame(b)
        if found != ax {
            // First run, or the banner moved: redo this backdrop at the real spot.
            ax = found
            try? "\(ax.minX) \(ax.minY) \(ax.width) \(ax.height)".write(to: frameURL, atomically: true, encoding: .utf8)
            showBackdrop(bd, around: ax)
            pump(0.3)
        }
        capture(ax, "real-\(bd)")
        print("real-\(bd) at \(ax)")
    }
    backdropWindow?.orderOut(nil)

case "cand":
    let name = args[1]
    let (p, backdrops) = parse(args[2...])
    let ax = loadFrame()
    for bd in backdrops {
        showBackdrop(bd, around: ax)
        pump(0.3)
        let panel = NSPanel(contentRect: nsRect(ax), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = p["shadow"] == "1"
        panel.contentView = mockBanner(ax.size, p)
        panel.orderFrontRegardless()
        pump(0.5)
        capture(ax, "cand-\(name)-\(bd)")
        panel.orderOut(nil)
    }
    backdropWindow?.orderOut(nil)

#if PROD
case "prod":
    // Keys: title subtitle body height scale tint=red
    let name = args[1]
    let (p, backdrops) = parse(args[2...])
    var ax = loadFrame()
    if let h = p["height"] { ax.size.height = CGFloat(Double(h)!) }
    let content = BannerContent(appName: "Script Editor", title: p["title"] ?? "Probe title",
                                subtitle: p["subtitle"] ?? "", body: p["body"] ?? "Probe body text",
                                appIcon: probeIcon)
    let manager = MainActor.assumeIsolated { CustomBannerManager() }
    // Glass samples what is behind it asynchronously, and the very first one in
    // a process takes longest. Without a throwaway first render the first
    // backdrop is captured showing whatever was on screen before it.
    showBackdrop(backdrops.first ?? "wallpaper", around: ax)
    MainActor.assumeIsolated {
        manager.showBanner(content: content, axTopLeft: ax.origin, width: ax.width, height: ax.height,
                           scale: 1, backgroundColor: .clear, autoDismissSeconds: 0,
                           animation: .fade, onOpen: {}, key: 0)
    }
    pump(1.0)
    MainActor.assumeIsolated { manager.dismiss(key: 0) }
    pump(0.5)
    for bd in backdrops {
        showBackdrop(bd, around: ax)
        pump(0.6)
        MainActor.assumeIsolated {
            manager.showBanner(content: content, axTopLeft: ax.origin, width: ax.width, height: ax.height,
                               scale: Double(p["scale"] ?? "1")!,
                               backgroundColor: p["tint"] == "red" ? .red : .clear,
                               autoDismissSeconds: 0, animation: .fade, onOpen: {}, key: 1)
        }
        pump(0.9)
        capture(ax, "cand-\(name)-\(bd)")
        MainActor.assumeIsolated { manager.dismiss(key: 1) }
        pump(0.5)
    }
    backdropWindow?.orderOut(nil)
#endif

default:
    print("usage: see the header of lab.swift")
}
