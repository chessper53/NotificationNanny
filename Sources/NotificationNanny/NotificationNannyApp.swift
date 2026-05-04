import SwiftUI

@main
struct NotificationNannyApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(coordinator.settings)
                .environmentObject(coordinator.repositioner)
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

    init() {
        repositioner.bind(to: settings)
    }
}
