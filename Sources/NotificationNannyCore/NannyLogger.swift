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
    private init() {}

    package func log(_ message: String, level: LogEntry.Level = .info, tag: String = "") {
        entries.append(LogEntry(timestamp: Date(), level: level, tag: tag, message: message))
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
