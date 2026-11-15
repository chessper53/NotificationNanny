import AppKit
import CoreGraphics

/// Screen Recording for the opening cover over the native panel and native widget images.
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
