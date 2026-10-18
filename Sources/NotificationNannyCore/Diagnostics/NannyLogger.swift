import AppKit
import Foundation
import UniformTypeIdentifiers

package struct LogEntry: Identifiable, Sendable {
    package let id = UUID()
    package let timestamp: Date
    package let level: Level
    package let tag: String
    package let message: String

    package enum Level: String, Sendable {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
    }
}

@MainActor
package final class NannyLogger: ObservableObject {
    package static let shared = NannyLogger()

    @Published package private(set) var entries: [LogEntry] = []

    private let cap = 1000
    /// NN_LOG_STDERR=1 mirrors the session log to stderr, for scripted runs
    /// (scripts/notify-lab) that can't open the in-app log.
    private let mirrorToStderr = ProcessInfo.processInfo.environment["NN_LOG_STDERR"] == "1"
    private var file: SessionLogFile?
    private let lineFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return fmt
    }()
    init() {}

    /// Mirrors the log to disk from here on, starting with what is already logged. Only the
    /// app calls this, once it knows it is the only instance: tests, and a second copy that
    /// is about to quit, must not push the running app's log aside.
    package func startWritingToDisk(in directory: URL = SessionLogFile.defaultDirectory) {
        guard file == nil else { return }
        let file = SessionLogFile(directory: directory)
        if !entries.isEmpty { file.append(exportText()) }
        self.file = file
    }

    /// The end of the previous session's log, when `crash` happened during that session.
    func logBefore(_ crash: CrashSummary?, maxLines: Int) -> String? {
        guard let crash, let file, let start = file.previousSessionStart, crash.date >= start,
              let text = file.previousSession, !text.isEmpty else { return nil }
        return text.trimmingCharacters(in: .newlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(maxLines).joined(separator: "\n")
    }

    package func log(_ message: String, level: LogEntry.Level = .info, tag: String = "") {
        let entry = LogEntry(timestamp: Date(), level: level, tag: tag, message: message)
        entries.append(entry)
        if mirrorToStderr {
            let tagPart = tag.isEmpty ? "" : "[\(tag)] "
            let stamp = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
            FileHandle.standardError.write(Data("\(stamp) [\(level.rawValue)] \(tagPart)\(message)\n".utf8))
        }
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
        if let file {
            file.append(line(for: entry))
            if file.isFull { file.replace(with: exportText()) }
        }
    }

    package func clear() { entries.removeAll() }

    package func saveToFile() {
        let text = exportText()
        guard let data = text.data(using: .utf8) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NotificationNanny Log.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    package func exportText() -> String {
        entries.map(line(for:)).joined(separator: "\n")
    }

    private func line(for e: LogEntry) -> String {
        let tagPart = e.tag.isEmpty ? "" : "[\(e.tag)] "
        return "\(lineFormatter.string(from: e.timestamp)) [\(e.level.rawValue)] \(tagPart)\(e.message)"
    }
}
