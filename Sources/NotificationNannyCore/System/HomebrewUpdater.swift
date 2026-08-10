import AppKit
import Foundation

/// Runs `brew upgrade --cask notificationnanny` in-process and streams
/// its output back to the UI.
///
/// Lifecycle: created once as a `@StateObject` on `SettingsView`. The
/// underlying `Process` survives independently — it will run to completion
/// even if the settings window is closed mid-update.
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

    // MARK: - Actions

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

        // Inherit the user environment so brew finds its own Ruby/git,
        // then override a few variables for clean machine-readable output.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"   // correct Homebrew variable (not HOMEBREW_COLOR)
        env["NO_COLOR"] = "1"            // respected by many CLI tools as a standard
        env["TERM"] = "dumb"             // last-resort fallback for anything that checks TERM
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
                    // Surface the most informative line: prefer lines that
                    // mention "error", otherwise fall back to the last line.
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

    /// Launches the already-updated app bundle and terminates the current process.
    /// A short sleep gives the current process time to exit cleanly before `open`
    /// fires — without it, macOS may bring the still-running instance to front
    /// instead of launching the new binary.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "sleep 1 && open \"\(path)\""]
        try? helper.run()
        NSApplication.shared.terminate(nil)
    }

    /// Resets the updater back to `.idle` so the banner can be dismissed or
    /// a new attempt made. No-op while an update is in progress.
    func reset() {
        guard case .running = state else {
            state = .idle
            outputLines = []
            return
        }
    }

    // MARK: - Helpers

    /// Strips ANSI escape sequences (e.g. `\u{1B}[31m`) from a string.
    /// Belt-and-suspenders fallback for tools that ignore NO_COLOR / TERM=dumb.
    private nonisolated static func stripANSI(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        return text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }
}
