import Foundation

/// Logs text lengths for privacy; isolated lab runs retain text for their checks.
enum LogPrivacy {
    static let showsText = ProcessInfo.processInfo.environment["NN_LAB"] == "1"

    /// `"the text"` in a lab run, `<42 chars>` otherwise.
    static func describe(_ text: String) -> String {
        guard showsText else { return "<\(text.count) chars>" }
        return "\"\(text.prefix(50).replacingOccurrences(of: "\n", with: "⏎"))\""
    }
}
