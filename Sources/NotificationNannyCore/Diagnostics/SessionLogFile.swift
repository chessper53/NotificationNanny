import Foundation

/// Keeps the current and previous session logs so crash context survives a restart.
final class SessionLogFile {
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotificationNanny/Logs", isDirectory: true)
    }

    let currentURL: URL
    let previousURL: URL
    private let maxBytes: Int
    private var handle: FileHandle?
    private var bytes = 0

    init(directory: URL, maxBytes: Int = 1_000_000) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        currentURL = directory.appendingPathComponent("session.log")
        previousURL = directory.appendingPathComponent("previous-session.log")
        self.maxBytes = maxBytes
        try? fm.removeItem(at: previousURL)
        try? fm.moveItem(at: currentURL, to: previousURL)
        fm.createFile(atPath: currentURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: currentURL)
    }

    deinit { try? handle?.close() }

    /// Write without user space buffering so a process crash does not lose pending lines.
    func append(_ text: String) {
        guard let handle else { return }
        let data = Data((text + "\n").utf8)
        bytes += data.count
        try? handle.write(contentsOf: data)
    }

    /// Past the size cap. The caller swaps the file for what it still holds in memory.
    var isFull: Bool { bytes > maxBytes }

    func replace(with text: String) {
        try? handle?.truncate(atOffset: 0)
        bytes = 0
        append(text)
    }

    var previousSession: String? { try? String(contentsOf: previousURL, encoding: .utf8) }

    /// When the previous session started. A rename keeps the creation date.
    var previousSessionStart: Date? {
        (try? FileManager.default.attributesOfItem(atPath: previousURL.path))?[.creationDate] as? Date
    }
}
