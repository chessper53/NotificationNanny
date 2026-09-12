import NotificationNannyCore
import SwiftUI
import AppKit
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
        settings = AppSettings()
        launchAtLogin = LaunchAtLogin()
        #if !DEBUG
        AppCoordinator.resetTCCIfBinaryChanged()
        #endif
        repositioner = NotificationRepositioner()
        super.init()
        repositioner.bind(to: settings)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = NotificationDisplayDelegate.shared
            // Requested once, silently, well before a test notification could ever be
            // needed — lets TestNotification skip the osascript subprocess for users
            // who grant it. Denial just means TestNotification keeps its existing
            // osascript fallback; no retry, no nagging.
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
        // The slashed bell covers "can't work" and "won't work" alike, so the icon
        // has to follow the enabled/snooze state too, not just the permission.
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

    /// Right-click quick actions, separate from the left-click Settings window. Built fresh
    /// each time so the "Pause"/"Resume" state is never stale. `statusItem.menu` is cleared
    /// immediately after (see `menuDidClose`) — leaving it set would make left-clicks pop this
    /// menu too, since AppKit prefers `NSStatusItem.menu` over `button.action` when both exist.
    private func showQuickActionsMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Looked up via LocalizationManager rather than NSLocalizedString: this menu rebuilds
        // fresh on every open, but NSLocalizedString resolves through Bundle.main, which is
        // fixed at process launch — it wouldn't hot-reload when the user picks a new language
        // from the General tab without an actual relaunch. LocalizationManager's bundle swaps
        // live, so this menu picks up the current language on its very next open.
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
        // See showQuickActionsMenu: clearing this restores button.action for left-clicks.
        DispatchQueue.main.async { [weak self] in self?.statusItem?.menu = nil }
    }

    private func statusItemScreen() -> NSScreen? {
        if let screen = statusItem?.button?.window?.screen { return screen }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    func openSettings(on screen: NSScreen? = nil) {
        if let win = settingsWindow {
            presentWindow(win, on: screen)
            return
        }
        let rootView = SettingsView()
            .environmentObject(settings)
            .environmentObject(repositioner)
            .environmentObject(launchAtLogin)
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "NotificationNanny Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 660, height: 640))
        window.minSize = NSSize(width: 660, height: 640)
        window.maxSize = NSSize(width: 660, height: 640)
        window.isReleasedWhenClosed = false
        window.center()
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

    private static func resetTCCIfBinaryChanged() {
        guard let execURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
              let mtime = attrs[.modificationDate] as? Date else { return }
        let key = "lastBinaryMtime"
        let stored = UserDefaults.standard.object(forKey: key) as? Date
        guard mtime != stored else { return }
        UserDefaults.standard.set(mtime, forKey: key)
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

    /// Settings writes are debounced so dragging doesn't hammer UserDefaults, which
    /// leaves a sub-second window where a crash or force-quit would lose the last
    /// edit. Deactivating is the natural end of an editing session and costs one
    /// write, so close that window here rather than relying on a clean terminate.
    func applicationDidResignActive(_ notification: Notification) {
        settings.flushPendingSaves()
    }

    func applicationWillTerminate(_ notification: Notification) {
        settings.flushPendingSaves()
    }

    private func autoEnableLoginItemIfNeeded() {
        let key = "didAutoEnableLoginItem"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        launchAtLogin.setEnabled(true)
        defaults.set(true, forKey: key)
    }
}
