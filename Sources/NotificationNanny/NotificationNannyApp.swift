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
    let settings = AppSettings()
    let repositioner = NotificationRepositioner()
    let launchAtLogin = LaunchAtLogin()

    init() {
        repositioner.bind(to: settings)
        autoEnableLoginItemIfNeeded()
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
