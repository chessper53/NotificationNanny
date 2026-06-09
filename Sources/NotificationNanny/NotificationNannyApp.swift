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
final class AppCoordinator: NSObject, ObservableObject {
    let settings: AppSettings
    let repositioner: NotificationRepositioner
    let launchAtLogin: LaunchAtLogin

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    override init() {
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
    }

    private func updateStatusIcon(hasPermission: Bool) {
        let name = hasPermission ? "bell.badge.fill" : "bell.slash.fill"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "NotificationNanny")
        img?.isTemplate = true
        statusItem?.button?.image = img
    }

    @objc private func statusItemClicked() {
        openSettings()
    }

    // MARK: - Settings window

    func openSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
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
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
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
