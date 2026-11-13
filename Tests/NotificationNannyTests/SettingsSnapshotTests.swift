import AppKit
import SwiftUI
import Testing
@testable import NotificationNannyCore

// Render demo data only when NN_SNAPSHOT_DIR is set.
// Render tab content rather than SettingsView to avoid starting AX observation on the user's
// desktop.
// Registered defaults remain in memory and personal settings never appear in captures.
@Suite("Settings snapshots") @MainActor
struct SettingsSnapshotTests {

    nonisolated static let outputDirectory = ProcessInfo.processInfo.environment["NN_SNAPSHOT_DIR"]

    // Website capture size excludes the sidebar from the original 660 by 640 point window.
    static let paneSize = NSSize(width: 509, height: 640)

    // Click Developer, then Activity log, using panel coordinates from the top left.
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
            // Keep the website's exceptions capture name for a selected Banner group.
            ("exceptions", AnyView(BannerTabView(initialScope: settings.appGroups.first?.id)), []),
            ("notification-center", AnyView(NotificationCenterTabView()), []),
            ("sounds", AnyView(SoundsTabView()), []),
            ("presets", AnyView(PresetsTabView()), []),
            ("general", AnyView(GeneralTabView()), []),
            ("diagnostics", AnyView(DebugTabView()), Self.diagnosticsClicks),
            ("help", AnyView(HelpTabView()), []),
        ]

        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let suffix = appearance == .aqua ? "-light" : ""
            for tab in tabs {
                let pane = ScrollView { tab.view.padding(16) }
                    // Avoid a legacy scroll gutter that changes the capture width when a mouse is
                    // attached.
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

    // MARK: Rendering

    private func render(_ view: some View, appearance: NSAppearance.Name, clicks: [NSPoint]) throws -> Data {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.paneSize)

        // Keep the window off every display so snapshots remain invisible.
        let window = KeyLookingWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: Self.paneSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // Allow layout, icon loading, and the initial preview animation to settle.
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        for click in clicks {
            // Window y increases upward.
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

        // Always render at Retina resolution, independent of the attached display.
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

    // MARK: Demo data

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

        // A fresh suite and registration defaults keep snapshots independent of persisted user
        // data.
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
        // Separate sample timestamps so the demo log does not repeat the same time.
        for (index, line) in lines.enumerated() {
            logger.log(line.0, tag: line.1)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15 + Double(index % 3) * 0.2))
        }
    }
}

/// Draw active AppKit controls without taking focus from the user's app.
private final class KeyLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }

    // Pin the backing scale so an offscreen window cannot upscale a 1x render into the Retina
    // bitmap.
    override var backingScaleFactor: CGFloat { 2 }
}
