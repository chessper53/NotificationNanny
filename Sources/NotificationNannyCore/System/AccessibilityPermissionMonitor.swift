@preconcurrency import ApplicationServices

@MainActor
package final class AccessibilityPermissionMonitor {
    package private(set) var hasPermission: Bool
    nonisolated(unsafe) private var pollTimer: Timer?

    package init() {
        hasPermission = AXIsProcessTrusted()
    }

    deinit { pollTimer?.invalidate() }

    func refresh() {
        hasPermission = AXIsProcessTrusted()
    }

    func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    // Poll every 1.5 seconds until granted, then call once on the main actor. Repeated starts are
    // harmless.
    func startPollingIfNeeded(onGranted: @escaping @MainActor () -> Void) {
        guard pollTimer == nil, !hasPermission else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refresh()
                if self.hasPermission {
                    timer.invalidate()
                    self.pollTimer = nil
                    onGranted()
                }
            }
        }
    }
}
