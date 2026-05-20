import NotificationNannyCore
import SwiftUI

@main
struct NotificationNannyApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(coordinator.settings)
                .environmentObject(coordinator.repositioner)
                .environmentObject(coordinator.launchAtLogin)
        } label: {
            Image(systemName: "bell.badge.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the long-lived app objects and wires them together at launch — so
/// observation starts immediately, not the first time the user opens the popover.
@MainActor
final class AppCoordinator: ObservableObject {
    let settings: AppSettings
    let repositioner: NotificationRepositioner
    let launchAtLogin: LaunchAtLogin

    init() {
        settings = AppSettings()
        launchAtLogin = LaunchAtLogin()
        // Must run before NotificationRepositioner.init(), which calls AXIsProcessTrusted().
        AppCoordinator.resetTCCIfBinaryChanged()
        repositioner = NotificationRepositioner()
        repositioner.bind(to: settings)
        Task { @MainActor [weak self] in self?.autoEnableLoginItemIfNeeded() }
    }

    /// If the binary has been replaced (e.g. a Homebrew upgrade), the old TCC
    /// grant is tied to the previous signature and will silently fail. Detect
    /// the change by comparing the executable's modification date and reset the
    /// Accessibility entry so the new binary can request a fresh grant.
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

    /// First time we're launched from /Applications, opt the user in to
    /// auto-launch. They can flip the toggle off later if they don't want it.
    private func autoEnableLoginItemIfNeeded() {
        let key = "didAutoEnableLoginItem"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        launchAtLogin.setEnabled(true)
        defaults.set(true, forKey: key)
    }
}
