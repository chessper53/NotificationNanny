import Foundation

/// What of a notification's text goes into the log: its length only. Logs are kept on disk
/// and go into bug reports, a GitHub URL among them, and a notification's text was there
/// even with its content blurred on screen. Lab runs (NN_LAB=1) show only the Lab apps'
/// notifications and keep the text, which their checks read.
enum LogPrivacy {
    static let showsText = ProcessInfo.processInfo.environment["NN_LAB"] == "1"

    /// `"the text"` in a lab run, `<42 chars>` otherwise.
    static func describe(_ text: String) -> String {
        guard showsText else { return "<\(text.count) chars>" }
        return "\"\(text.prefix(50).replacingOccurrences(of: "\n", with: "⏎"))\""
    }
}
