import Foundation

/// What macOS recorded about a NotificationNanny crash.
struct CrashSummary: Equatable {
    let date: Date
    let appVersion: String?
    /// Exception type and signal, e.g. "EXC_BREAKPOINT (SIGTRAP)".
    let exception: String?
    /// The Swift runtime's own words, e.g. "Fatal error: Index out of range".
    let message: String?
    /// The innermost frame of our own code on the crashed thread.
    let frame: String?
}

/// Reads the crash reports macOS writes to ~/Library/Logs/DiagnosticReports. When the app
/// just vanishes from the menu bar, these hold the only record of where it went down.
enum CrashReports {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    static func latest(in directory: URL = directory, processName: String = "NotificationNanny") -> CrashSummary? {
        let key = URLResourceKey.contentModificationDateKey
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [key])
        else { return nil }
        let modified = { (url: URL) in
            (try? url.resourceValues(forKeys: [key]))?.contentModificationDate ?? .distantPast
        }
        guard let newest = urls
            .filter({ $0.pathExtension == "ips" && $0.lastPathComponent.hasPrefix(processName + "-") })
            .max(by: { modified($0) < modified($1) }),
              let text = try? String(contentsOf: newest, encoding: .utf8) else { return nil }
        return parse(text, processName: processName, fallbackDate: modified(newest))
    }

    /// An .ips file is a one-line JSON header followed by a JSON body.
    static func parse(_ text: String, processName: String, fallbackDate: Date) -> CrashSummary? {
        let parts = text.split(separator: "\n", maxSplits: 1)
        guard parts.count == 2,
              let header = json(parts[0]),
              (header["app_name"] as? String ?? header["name"] as? String) == processName,
              let body = json(parts[1]) else { return nil }

        // "2026-10-17 12:45:22.00 +0200"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        let date = (header["timestamp"] as? String).flatMap(formatter.date(from:)) ?? fallbackDate

        var exception: String?
        if let exc = body["exception"] as? [String: Any], let type = exc["type"] as? String {
            exception = (exc["signal"] as? String).map { "\(type) (\($0))" } ?? type
        }

        let message = (body["asi"] as? [String: [String]])?.values.flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return CrashSummary(date: date, appVersion: header["app_version"] as? String,
                            exception: exception, message: message,
                            frame: crashedFrame(in: body, processName: processName))
    }

    private static func crashedFrame(in body: [String: Any], processName: String) -> String? {
        guard let threads = body["threads"] as? [[String: Any]],
              let index = body["faultingThread"] as? Int, threads.indices.contains(index),
              let frames = threads[index]["frames"] as? [[String: Any]] else { return nil }
        let images = (body["usedImages"] as? [[String: Any]])?.map { $0["name"] as? String } ?? []
        let isOurs = { (frame: [String: Any]) in
            guard let i = frame["imageIndex"] as? Int, images.indices.contains(i) else { return false }
            return images[i] == processName
        }
        // Our own frame says where to look; failing that, whatever crashed is better than nothing.
        guard let frame = frames.first(where: isOurs) ?? frames.first(where: { $0["symbol"] != nil })
        else { return nil }

        var text: String
        if let symbol = frame["symbol"] as? String {
            text = symbol
            if let offset = frame["symbolLocation"] as? Int { text += " + \(offset)" }
        } else {
            text = "\(processName) + \(frame["imageOffset"] as? Int ?? 0)"
        }
        if let file = frame["sourceFile"] as? String {
            text += " (\(file)\((frame["sourceLine"] as? Int).map { ":\($0)" } ?? ""))"
        }
        return text
    }

    private static func json(_ text: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}
