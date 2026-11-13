import Foundation
import ServiceManagement

/// Login registration depends on bundle ID and launch path; use a stable installation location.
@MainActor
package final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    package init() {
        refresh()
    }

    package func refresh() {
        guard #available(macOS 13, *) else {
            isEnabled = false
            return
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    package func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13, *) else {
            lastError = "Requires macOS 13 or later"
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }
}
