import AppKit
import CoreGraphics

/// Screen Recording, which the custom Notification Center needs only to show widgets:
/// they are drawn by their own apps, and a picture of the real one is all there is to show.
/// Asked for only when widgets are turned on.
@MainActor
package final class ScreenRecordingPermission: ObservableObject {
    package static let shared = ScreenRecordingPermission()

    @Published package private(set) var isGranted = CGPreflightScreenCaptureAccess()

    package func refresh() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != isGranted { isGranted = granted }
    }

    /// Shows the system's prompt the first time; after that macOS only lists the app in
    /// System Settings, so the tab also offers the way there.
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
