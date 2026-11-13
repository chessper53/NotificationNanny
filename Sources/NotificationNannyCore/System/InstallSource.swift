import Foundation

/// Detect Homebrew by its Caskroom directory; both installation methods use the same app bundle
/// path.
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
