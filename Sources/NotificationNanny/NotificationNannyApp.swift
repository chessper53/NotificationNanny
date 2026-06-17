import NotificationNannyCore
import SwiftUI
import AppKit
import UserNotifications
import Combine

@main
struct NotificationNannyApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        // LSUIElement apps have no menu bar, so this empty Settings scene satisfies
        // the App protocol without auto-showing any window on launch.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject, NSApplicationDelegate {
    let settings: AppSettings
    let repositioner: NotificationRepositioner
    let launchAtLogin: LaunchAtLogin

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        // Single-instance guard. A second instance would attach its own AXObserver to
        // NotificationCenterUI (two processes fighting over banner positions) and run the
        // TCC reset below, revoking Accessibility from the live instance. Hand off to the
        // existing one and exit before any of that setup happens.
        AppCoordinator.terminateIfAlreadyRunning()
        settings = AppSettings()
        launchAtLogin = LaunchAtLogin()
        #if !DEBUG
        AppCoordinator.resetTCCIfBinaryChanged()
        #endif
        repositioner = NotificationRepositioner()
        super.init()
        repositioner.bind(to: settings)
        // UNUserNotificationCenter.current() aborts if the process has no bundle ID
        // (e.g. raw binary run by the debugger outside a .app wrapper).
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = NotificationDisplayDelegate.shared
        }
        Task { @MainActor [weak self] in self?.autoEnableLoginItemIfNeeded() }
        setupStatusItem()
        observePermission()
        NSApp.delegate = self
        // Auto-open settings if Accessibility permission hasn't been granted yet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.repositioner.hasAccessibilityPermission else { return }
            self.openSettings()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        updateStatusIcon(hasPermission: repositioner.hasAccessibilityPermission)
        button.action = #selector(statusItemClicked)
        button.target = self
    }

    private func observePermission() {
        repositioner.$hasAccessibilityPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateStatusIcon(hasPermission: $0) }
            .store(in: &cancellables)
        settings.$hideMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hide in self?.statusItem?.isVisible = !hide }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(hasPermission: Bool) {
        let name = hasPermission ? "bell.badge.fill" : "bell.slash.fill"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "NotificationNanny")
        img?.isTemplate = true
        statusItem?.button?.image = img
    }

    @objc private func statusItemClicked() {
        openSettings(on: statusItemScreen())
    }

    /// The display whose menu bar currently hosts the status item — i.e. the one the
    /// user just clicked. Falls back to the screen under the mouse.
    private func statusItemScreen() -> NSScreen? {
        if let screen = statusItem?.button?.window?.screen { return screen }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    // MARK: - Settings window

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

    /// Brings an existing settings window to the front. As an `LSUIElement` accessory
    /// app, the macOS 14+ cooperative `NSApp.activate()` will not pull our window above
    /// the currently active app — so the window would stay hidden behind whatever the
    /// user clicked into. `ignoringOtherApps` + `orderFrontRegardless` forces it forward.
    private func presentWindow(_ window: NSWindow, on screen: NSScreen? = nil) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        if let screen { centerWindow(window, on: screen) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Center `window` on the given screen's visible area, so it opens on whichever
    /// display the menu-bar icon was clicked rather than always on the primary screen.
    private func centerWindow(_ window: NSWindow, on screen: NSScreen) {
        let vf = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2,
                                      y: vf.midY - size.height / 2))
    }

    // MARK: - Single-instance guard

    /// If another copy of this app (same bundle ID, different PID) is already running,
    /// bring it forward and terminate this process. Skipped when there is no bundle ID
    /// (e.g. a raw binary launched by the debugger), where the lookup wouldn't apply.
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

    // MARK: - TCC reset on binary change

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

    // MARK: - Notification display delegate

    private final class NotificationDisplayDelegate: NSObject, UNUserNotificationCenterDelegate {
        static let shared = NotificationDisplayDelegate()
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }

    // MARK: - App delegate

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settings.hideMenuBarIcon { openSettings() }
        return true
    }

    // MARK: - Login item

    private func autoEnableLoginItemIfNeeded() {
        let key = "didAutoEnableLoginItem"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        launchAtLogin.setEnabled(true)
        defaults.set(true, forKey: key)
    }
}
