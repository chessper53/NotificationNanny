import NotificationNannyCore
import SwiftUI
import AppKit
import ApplicationServices
import UserNotifications
import Combine

@main
struct NotificationNannyApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject, NSApplicationDelegate, NSMenuDelegate {
    let settings: AppSettings
    let repositioner: NotificationRepositioner
    let launchAtLogin: LaunchAtLogin

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        AppCoordinator.terminateIfAlreadyRunning()
        // Only a bundled app may rotate the session log; lab runs use a separate folder.
        if Bundle.main.bundleIdentifier != nil {
            if let dir = ProcessInfo.processInfo.environment["NN_LOG_DIR"] {
                NannyLogger.shared.startWritingToDisk(in: URL(fileURLWithPath: dir, isDirectory: true))
            } else {
                NannyLogger.shared.startWritingToDisk()
            }
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            NannyLogger.shared.log("NotificationNanny v\(version) started", tag: "App")
        }
        do {
            settings = try AppSettings.forAppLaunch()
        } catch {
            FileHandle.standardError.write(Data("Invalid E2E settings: \(error)\n".utf8))
            exit(64)
        }
        if ProcessInfo.processInfo.environment["NN_E2E_DIRECTORY"] != nil {
            NannyLogger.shared.log("E2E settings isolated", tag: "Test")
        }
        NannyLogger.shared.logSessionHeader(settings: settings)
        launchAtLogin = LaunchAtLogin()
        #if !DEBUG
        if ProcessInfo.processInfo.environment["NN_E2E_DIRECTORY"] == nil {
            AppCoordinator.resetTCCIfBinaryChanged()
        }
        #endif
        repositioner = NotificationRepositioner()
        super.init()
        repositioner.bind(to: settings)
        if Bundle.main.bundleIdentifier != nil, ProcessInfo.processInfo.environment["NN_E2E_DIRECTORY"] == nil {
            UNUserNotificationCenter.current().delegate = NotificationDisplayDelegate.shared
            // Request once so test notifications can avoid the osascript fallback when allowed.
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        Task { @MainActor [weak self] in self?.autoEnableLoginItemIfNeeded() }
        setupStatusItem()
        observePermission()
        observeColorPanelActivation()
        NSApp.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.repositioner.hasAccessibilityPermission else { return }
            self.openSettings()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        updateStatusIcon()
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observePermission() {
        // The slashed bell also reflects disabled and snoozed states.
        Publishers.CombineLatest3(
            repositioner.$hasAccessibilityPermission,
            settings.$isEnabled,
            settings.$snoozedUntil
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in self?.updateStatusIcon() }
        .store(in: &cancellables)
        settings.$hideMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hide in self?.statusItem?.isVisible = !hide }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        let glyph = NannyGlyph.forState(
            hasPermission: repositioner.hasAccessibilityPermission,
            isActive: settings.isActive
        )
        let img = glyph.image(pointSize: 20)
            ?? NSImage(systemSymbolName: glyph.fallbackSymbolName, accessibilityDescription: nil)
        img?.isTemplate = true
        img?.accessibilityDescription = "NotificationNanny"
        statusItem?.button?.image = img
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickActionsMenu()
        } else {
            openSettings(on: statusItemScreen())
        }
    }

    /// Rebuild quick actions on each open and clear the menu on close to restore button actions.
    private func showQuickActionsMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Use the current localization bundle so language changes apply without relaunching.
        let loc = LocalizationManager.shared

        if settings.isSnoozed, let until = settings.snoozedUntil {
            let format = loc.string("Resume (paused until %@)")
            let item = NSMenuItem(
                title: String(format: format, Self.menuTimeFormatter.string(from: until)),
                action: #selector(resumeFromMenu), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let pauseMenu = NSMenu()
            let options: [(String, Int)] = [
                (loc.string("15 minutes"), 15),
                (loc.string("30 minutes"), 30),
                (loc.string("1 hour"), 60),
            ]
            for (label, minutes) in options {
                let item = NSMenuItem(title: label, action: #selector(pauseFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                pauseMenu.addItem(item)
            }
            let pauseItem = NSMenuItem(title: loc.string("Pause for…"), action: nil, keyEquivalent: "")
            pauseItem.submenu = pauseMenu
            menu.addItem(pauseItem)
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: loc.string("Settings…"),
                                      action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: loc.string("Quit NotificationNanny"),
                                  action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    private static let menuTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    @objc private func pauseFromMenu(_ sender: NSMenuItem) {
        settings.snooze(minutes: sender.tag)
    }

    @objc private func resumeFromMenu() {
        settings.endSnooze()
    }

    @objc private func openSettingsFromMenu() {
        openSettings(on: statusItemScreen())
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Clearing the menu restores button actions for left clicks.
        DispatchQueue.main.async { [weak self] in self?.statusItem?.menu = nil }
    }

    private func statusItemScreen() -> NSScreen? {
        if let screen = statusItem?.button?.window?.screen { return screen }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    static let settingsDefaultSize = NSSize(width: 640, height: 480)

    func openSettings(on screen: NSScreen? = nil) {
        if let win = settingsWindow {
            presentWindow(win, on: screen)
            return
        }
        let rootView = SettingsView()
            .environmentObject(settings)
            .environmentObject(repositioner)
            .environmentObject(launchAtLogin)
        let hosting = NSViewController()
        // Accept the first drag while Settings is inactive behind Notification Center.
        let hostingView = FirstClickHostingView(rootView: rootView)
        hosting.view = hostingView
        // Pass on the content minimum while AppKit controls the saved and default window size.
        hostingView.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "NotificationNanny Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.settingsDefaultSize)
        window.contentMinSize = SettingsView.minimumContentSize
        window.isReleasedWhenClosed = false
        window.center()
        // Restore after centering so a saved frame wins. The new name discards obsolete oversized
        // frames.
        window.setFrameAutosaveName("NotificationNannySettings")
        // Restored frames can be smaller than minSize, so clamp them explicitly.
        let content = window.contentLayoutRect.size
        let minimum = SettingsView.minimumContentSize
        if content.width < minimum.width || content.height < minimum.height {
            window.setContentSize(NSSize(width: max(content.width, minimum.width),
                                         height: max(content.height, minimum.height)))
        }
        settingsWindow = window
        presentWindow(window, on: screen)
    }

    private func presentWindow(_ window: NSWindow, on screen: NSScreen? = nil) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        if let screen { centerWindow(window, on: screen) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func centerWindow(_ window: NSWindow, on screen: NSScreen) {
        let vf = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2,
                                      y: vf.midY - size.height / 2))
    }

    private func observeColorPanelActivation() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow,
                  NSStringFromClass(type(of: window)) == "NSColorPanel" else { return }
            Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
        }
    }

    private static func terminateIfAlreadyRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != myPID }
        guard let existing else { return }
        NSLog("NotificationNanny: instance already running (pid %d) — exiting.", existing.processIdentifier)
        existing.activate()
        exit(0)
    }

    /// Reset stale Accessibility grants only when the binary changed and the current grant is
    /// invalid.
    private static func resetTCCIfBinaryChanged() {
        guard let execURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
              let mtime = attrs[.modificationDate] as? Date else { return }
        let key = "lastBinaryMtime"
        let stored = UserDefaults.standard.object(forKey: key) as? Date
        guard mtime != stored else { return }
        UserDefaults.standard.set(mtime, forKey: key)
        guard !AXIsProcessTrusted() else { return }
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.launchPath = "/usr/bin/tccutil"
            task.arguments = ["reset", "Accessibility", "com.notificationnanny.app"]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            try? task.run()
            task.waitUntilExit()
        }
    }

    private final class NotificationDisplayDelegate: NSObject, UNUserNotificationCenterDelegate {
        static let shared = NotificationDisplayDelegate()
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settings.hideMenuBarIcon { openSettings() }
        return true
    }

    /// Flush pending settings when editing ends, without relying on a clean termination.
    func applicationDidResignActive(_ notification: Notification) {
        settings.flushPendingSaves()
    }

    func applicationWillTerminate(_ notification: Notification) {
        settings.flushPendingSaves()
        repositioner.prepareForQuit()
    }

    private func autoEnableLoginItemIfNeeded() {
        guard ProcessInfo.processInfo.environment["NN_E2E_DIRECTORY"] == nil else { return }
        let key = "didAutoEnableLoginItem"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        launchAtLogin.setEnabled(true)
        defaults.set(true, forKey: key)
    }
}
