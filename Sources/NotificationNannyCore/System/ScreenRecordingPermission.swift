import AppKit
import CoreGraphics

/// Request Screen Recording only when native widget captures are enabled.
@MainActor
package final class ScreenRecordingPermission: ObservableObject {
    package static let shared = ScreenRecordingPermission()

    @Published package private(set) var isGranted = CGPreflightScreenCaptureAccess()

    package func refresh() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != isGranted { isGranted = granted }
    }

    /// macOS prompts only on the first request; later attempts need a System Settings link.
    package func request() {
        CGRequestScreenCaptureAccess()
        refresh()
    }

    package func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
