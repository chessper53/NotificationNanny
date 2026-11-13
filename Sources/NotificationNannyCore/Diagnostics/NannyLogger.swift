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
        /// Routine detail: in the log view while the app runs, never in the file or a report.
        case debug = "DEBUG"
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
    /// NN_LOG_STDERR=1 mirrors the session log for scripted runs.
    private let mirrorToStderr = ProcessInfo.processInfo.environment["NN_LOG_STDERR"] == "1"
    private var file: SessionLogFile?
    private let lineFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return fmt
    }()
    init() {}

    /// Starts disk logging after the instance check; tests and duplicate instances must not rotate
    /// it.
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

    /// Coalesce identical lines only; changing numbers can distinguish separate events.
    private var lastKey: String?
    private var lastAt = Date.distantPast
    private var repeats = 0
    private static let repeatWindow: TimeInterval = 60

    package func log(_ message: String, level: LogEntry.Level = .info, tag: String = "") {
        // Scripted runs read every line as it comes, repeats and detail included.
        if mirrorToStderr {
            let tagPart = tag.isEmpty ? "" : "[\(tag)] "
            let stamp = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
            FileHandle.standardError.write(Data("\(stamp) [\(level.rawValue)] \(tagPart)\(message)\n".utf8))
        }
        let now = Date()
        if level != .debug {
            let key = "\(level.rawValue)|\(tag)|\(message)"
            if key == lastKey, now.timeIntervalSince(lastAt) < Self.repeatWindow {
                repeats += 1
                lastAt = now
                return
            }
            flushRepeats()
            lastKey = key
            lastAt = now
        }
        append(LogEntry(timestamp: now, level: level, tag: tag, message: message))
    }

    private func flushRepeats() {
        guard repeats > 0, let last = entries.last(where: { $0.level != .debug }) else { repeats = 0; return }
        let n = repeats
        repeats = 0
        append(LogEntry(timestamp: lastAt, level: last.level, tag: last.tag,
                        message: "↑ the same \(n) more time\(n == 1 ? "" : "s"), last at \(lineFormatter.string(from: lastAt).suffix(12))"))
    }

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
        guard entry.level != .debug, let file else { return }
        file.append(line(for: entry))
        if file.isFull { file.replace(with: exportText()) }
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

    /// Exports without debug detail and includes a summary of pending repeats.
    package func exportText() -> String {
        var lines = entries.filter { $0.level != .debug }.map(line(for:))
        if repeats > 0 { lines.append("… the line above \(repeats) more time\(repeats == 1 ? "" : "s") so far") }
        return lines.joined(separator: "\n")
    }

    private func line(for e: LogEntry) -> String {
        let tagPart = e.tag.isEmpty ? "" : "[\(e.tag)] "
        return "\(lineFormatter.string(from: e.timestamp)) [\(e.level.rawValue)] \(tagPart)\(e.message)"
    }
}
