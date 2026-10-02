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
    private init() {}

    package func log(_ message: String, level: LogEntry.Level = .info, tag: String = "") {
        entries.append(LogEntry(timestamp: Date(), level: level, tag: tag, message: message))
        if mirrorToStderr {
            let tagPart = tag.isEmpty ? "" : "[\(tag)] "
            let stamp = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
            FileHandle.standardError.write(Data("\(stamp) [\(level.rawValue)] \(tagPart)\(message)\n".utf8))
        }
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
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
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { e in
            let tagPart = e.tag.isEmpty ? "" : "[\(e.tag)] "
            return "\(fmt.string(from: e.timestamp)) [\(e.level.rawValue)] \(tagPart)\(e.message)"
        }.joined(separator: "\n")
    }
}
