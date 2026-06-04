import Foundation

package struct LogEntry: Identifiable, Sendable {
    package let id = UUID()
    package let timestamp: Date
    package let level: Level
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

    private let cap = 500
    private init() {}

    package func log(_ message: String, level: LogEntry.Level = .info) {
        entries.append(LogEntry(timestamp: Date(), level: level, message: message))
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
    }

    package func clear() { entries.removeAll() }

    package func exportText() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { e in
            "\(fmt.string(from: e.timestamp)) [\(e.level.rawValue)] \(e.message)"
        }.joined(separator: "\n")
    }
}
