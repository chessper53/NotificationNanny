import AppKit
import Foundation

/// Runs a Homebrew cask upgrade and streams output; the process can finish after Settings closes.
@MainActor
final class HomebrewUpdater: ObservableObject {

    enum State: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var outputLines: [String] = []

    private var process: Process?

    // MARK: Actions

    func start() {
        guard case .idle = state else { return }
        guard let brew = InstallSource.brewExecutable else {
            state = .failed("brew not found — is Homebrew installed?")
            return
        }

        state = .running
        outputLines = []

        let p = Process()
        p.executableURL = URL(fileURLWithPath: brew)
        p.arguments = ["upgrade", "--cask", "notificationnanny"]

        // Inherit Homebrew's environment, suppress colors, and disable interactive behavior.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text
                .components(separatedBy: .newlines)
                .map { Self.stripANSI($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.outputLines.append(contentsOf: lines)
            }
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                process = nil
                if proc.terminationStatus == 0 {
                    state = .succeeded
                } else {
                    let hint = outputLines.last(where: { $0.localizedCaseInsensitiveContains("error") })
                        ?? outputLines.last
                        ?? "Exited with code \(proc.terminationStatus)"
                    state = .failed(hint)
                }
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Delay reopening the updated bundle until this process exits so macOS launches the new
    /// binary.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Pass the path as an argument so shell metacharacters remain literal.
        helper.arguments = ["-c", "sleep 1 && open \"$1\"", "relaunch", path]
        do {
            try helper.run()
        } catch {
            // Keep running if the relaunch helper cannot start.
            NannyLogger.shared.log("Couldn't relaunch after updating (\(error.localizedDescription)) — quit and reopen NotificationNanny",
                                   level: .error, tag: "Update")
            return
        }
        NSApplication.shared.terminate(nil)
    }

    /// Reset when idle or finished; ignore resets during an update.
    func reset() {
        guard case .running = state else {
            state = .idle
            outputLines = []
            return
        }
    }

    // MARK: Helpers

    /// Strip ANSI escapes from tools that ignore color suppression variables.
    private nonisolated static func stripANSI(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        return text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }
}
