import Foundation

/// Identifies how the running app was installed on this machine.
///
/// Homebrew cask installs leave a Caskroom directory even though the `.app`
/// itself is moved to `/Applications`. Checking for that directory is more
/// reliable than inspecting `Bundle.main.bundlePath`, which is the same path
/// (`/Applications/NotificationNanny.app`) for both install methods.
enum InstallSource {
    case homebrew
    case direct

    static var current: InstallSource {
        let caskroomRoots = [
            "/opt/homebrew/Caskroom/notificationnanny",
            "/usr/local/Caskroom/notificationnanny",
        ]
        return caskroomRoots.contains(where: FileManager.default.fileExists(atPath:))
            ? .homebrew : .direct
    }

    /// Absolute path to the `brew` binary, or `nil` if Homebrew is not installed.
    static var brewExecutable: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
