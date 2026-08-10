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
final class AppCoordinator: NSObject, ObservableObject, NSApplicationDelegate {
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

    private func autoEnableLoginItemIfNeeded() {
        let key = "didAutoEnableLoginItem"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        launchAtLogin.setEnabled(true)
        defaults.set(true, forKey: key)
    }
}
