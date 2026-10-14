import AppKit
import SwiftUI
import Testing
@testable import NotificationNannyCore

// Renders every Settings tab to PNG, in dark and light, for the landing page
// (scripts/capture-screenshots.sh turns them into site/assets/screenshots/*.webp).
// Skipped unless NN_SNAPSHOT_DIR names an output directory, so a normal test run
// never draws anything.
//
// Deliberately renders each tab's content view, not SettingsView: SettingsView's
// onAppear starts the AX observer whenever the process is trusted, and a test run
// from a trusted terminal would then move real notification banners alongside the
// installed app. The site crops the sidebar off anyway and draws its own.
//
// The settings are demo data, registered in memory only (register(defaults:)
// never persists), so the user's own groups, presets and log never appear and
// nothing is written to their preferences.
@Suite("Settings snapshots") @MainActor
struct SettingsSnapshotTests {

    nonisolated static let outputDirectory = ProcessInfo.processInfo.environment["NN_SNAPSHOT_DIR"]

    // The content pane of the 660 x 640 pt window the site's screenshots have always
    // shown: the window less the 150 pt sidebar and its 1 pt divider.
    static let paneSize = NSSize(width: 509, height: 640)

    // Where the Diagnostics tab's collapsed "Developer" row sits, then the "Activity
    // log" row inside it once that opens, in pane points from the top left. Clicked
    // open in turn so the screenshot shows the log.
    static let diagnosticsClicks = [NSPoint(x: 72, y: 151), NSPoint(x: 87, y: 423)]

    @Test(.enabled(if: outputDirectory != nil))
    func renderEveryTab() throws {
        let directory = URL(fileURLWithPath: try #require(Self.outputDirectory), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let settings = makeDemoSettings(knownAppsFile: directory.appendingPathComponent("known_apps.json"))
        let repositioner = NotificationRepositioner(logger: .shared)
        let launchAtLogin = LaunchAtLogin()
        fillDemoLog()

        let tabs: [(name: String, view: AnyView, clicks: [NSPoint])] = [
            ("position", AnyView(PositionTabView()), []),
            ("banner", AnyView(BannerTabView()), []),
            ("exceptions", AnyView(ExceptionsTabView()), []),
            ("presets", AnyView(PresetsTabView()), []),
            ("general", AnyView(GeneralTabView()), []),
            ("diagnostics", AnyView(DebugTabView()), Self.diagnosticsClicks),
            ("help", AnyView(HelpTabView()), []),
        ]

        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let suffix = appearance == .aqua ? "-light" : ""
            for tab in tabs {
                // The same wrapper SettingsView puts around the active tab.
                let pane = ScrollView { tab.view.padding(16) }
                    // Overlay-style: no legacy scroller gutter narrowing the content
                    // when the machine has a mouse attached.
                    .scrollIndicators(.never)
                    .frame(width: Self.paneSize.width, height: Self.paneSize.height)
                    .background(Color.nannyWindow)
                    .tint(Color.nannyProminent)
                    // Draw as the frontmost window does, so prominent buttons keep
                    // their accent fill instead of the inactive grey.
                    .environment(\.controlActiveState, .key)
                    // Numbers like the display size read 5,120 rather than the
                    // machine's regional grouping.
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .environmentObject(settings)
                    .environmentObject(repositioner)
                    .environmentObject(launchAtLogin)
                let png = try render(pane, appearance: appearance, clicks: tab.clicks)
                try png.write(to: directory.appendingPathComponent("\(tab.name)\(suffix).png"))
            }
        }
    }

    // MARK: - Rendering

    private func render(_ view: some View, appearance: NSAppearance.Name, clicks: [NSPoint]) throws -> Data {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.paneSize)

        // Borderless and far off every display, so nothing ever shows on screen.
        let window = KeyLookingWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: Self.paneSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // Let SwiftUI lay out, load app icons, and finish the Banner tab's preview
        // animation, which plays once on appear.
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        for click in clicks {
            // Window coordinates run bottom-up.
            let location = NSPoint(x: click.x, y: Self.paneSize.height - click.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        }
        host.layoutSubtreeIfNeeded()

        // Always 2x, whatever display the machine has, to match the Retina captures
        // the site was built around.
        let scale: CGFloat = 2
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(Self.paneSize.width * scale), pixelsHigh: Int(Self.paneSize.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = Self.paneSize
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    // MARK: - Demo data

    private func makeDemoSettings(knownAppsFile: URL) -> AppSettings {
        // Apps that ship with macOS, so their icons resolve on any Mac.
        let groups = [
            AppGroup(name: "Messages", appNames: ["Messages", "FaceTime"],
                     placement: ScreenPlacement(position: .bottomRight, xOffset: 0, yOffset: 0),
                     bannerScale: 1.25),
            AppGroup(name: "Calendar", appNames: ["Calendar", "Reminders"],
                     placement: ScreenPlacement(position: .topCenter, xOffset: 0, yOffset: 0),
                     bannerTint: BannerTint(r: 0.91, g: 0.51, b: 0.23)),
            AppGroup(name: "Mail", appNames: ["Mail"],
                     placement: ScreenPlacement(position: .topLeft, xOffset: 0, yOffset: 0)),
        ]
        let presets = [
            Preset(name: "Desk", placements: [:], bannerScale: 1.0, appGroups: groups),
            Preset(name: "Laptop only", placements: [:], bannerScale: 0.9),
            Preset(name: "Presenting", placements: [:], autoDismissSeconds: 4, pauseWhileStreaming: true),
        ]
        let encoder = JSONEncoder()

        // A fresh suite name each run: nothing on disk to read back, and the
        // registration domain below is never written out.
        let defaults = UserDefaults(suiteName: "NotificationNannySnapshots.\(UUID().uuidString)")!
        defaults.register(defaults: [
            "appGroups": (try? encoder.encode(groups)) ?? Data(),
            "presets": (try? encoder.encode(presets)) ?? Data(),
            "knownAppNames": ["Calendar", "FaceTime", "Mail", "Messages", "Notes", "Reminders"],
            "settingsAppearance": "system",
            "holdWhileAsleep": true,
            "pauseDuringFocus": true,
        ])
        return AppSettings(defaults: defaults, knownAppsFileURL: knownAppsFile)
    }

    private func fillDemoLog() {
        let logger = NannyLogger.shared
        logger.clear()
        let lines: [(String, String)] = [
            ("Observer started — NC PID 812", "AX"),
            ("Displays after launch: 1 — forced target id=0", "Display"),
            ("Window created — Messages", "AX"),
            ("Window created — Calendar", "AX"),
            ("Window destroyed", "AX"),
            ("Display sleeping — holding banners", "System"),
            ("Display woke — repositioning 2 held banner(s)", "System"),
            ("Window created — Mail", "AX"),
        ]
        // Entries are stamped when logged; a pause between them keeps the log from
        // showing one identical timestamp on every line.
        for (index, line) in lines.enumerated() {
            logger.log(line.0, tag: line.1)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15 + Double(index % 3) * 0.2))
        }
    }
}

/// Reports itself as key so AppKit-backed controls draw in their active state,
/// without the test process ever taking focus from whatever the user is doing.
private final class KeyLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }

    // The window sits off every display, so AppKit would take its scale from the
    // main one, which may be a 1x monitor; the 2x bitmap then holds a blurry
    // upscale. Pinning it to 2 makes every layer draw at Retina resolution.
    override var backingScaleFactor: CGFloat { 2 }
}
