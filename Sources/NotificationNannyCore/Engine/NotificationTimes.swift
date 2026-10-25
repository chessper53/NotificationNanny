import Foundation

/// When each notification arrived, for the custom Notification Center.
///
/// Notification Center draws a time on every row but doesn't put it in its accessibility
/// tree, so the app notes it itself: the moment a banner is first seen, keyed by the
/// banner's `AXIdentifier`. A notification keeps that identifier as a row in the panel,
/// expanded stacks included, and a collapsed stack carries its newest notification's
/// (measured on 27.0, scripts/panel-lab `run.sh ids`).
///
/// A row first seen in an open panel that was already there when it opened came in
/// while the app wasn't watching, so its time is unknown and nothing is shown for it
/// rather than a wrong one.
@MainActor
final class NotificationTimes {
    private struct Entry: Codable {
        let date: Date
        let exact: Bool
    }

    private var entries: [String: Entry] = [:]
    private let fileURL: URL?
    private var pendingSave: DispatchWorkItem?

    /// Times older than this are dropped even if the row is still listed.
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
    }

    /// Next to the app's other files, or in a lab run's own folder (NN_LOG_DIR).
    static let defaultFileURL: URL = {
        if let dir = ProcessInfo.processInfo.environment["NN_LOG_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("notification_times.json")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("NotificationNanny", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notification_times.json")
    }()

    /// Seen arriving: as a banner, or as a new row while the panel was open.
    func noteArrival(_ id: String, at date: Date = Date()) {
        guard entries[id] == nil else { return }
        entries[id] = Entry(date: date, exact: true)
        scheduleSave()
    }

    /// Seen for the first time in a panel that already listed it: arrived at some unknown
    /// moment before now. Remembered, so it isn't later taken for a new arrival.
    func noteAlreadyListed(_ id: String, at date: Date = Date()) {
        guard entries[id] == nil else { return }
        entries[id] = Entry(date: date, exact: false)
        scheduleSave()
    }

    /// The time to show for `id`, if it is known.
    func arrival(of id: String) -> Date? {
        guard let entry = entries[id], entry.exact else { return nil }
        return entry.date
    }

    /// The panel lists every notification there is, so anything not in it is gone.
    func prune(keeping ids: Set<String>, now: Date = Date()) {
        let kept = entries.filter { ids.contains($0.key) && now.timeIntervalSince($0.value.date) < Self.maxAge }
        guard kept.count != entries.count else { return }
        entries = kept
        scheduleSave()
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    /// Writes now instead of after the usual second's wait.
    func flush() {
        pendingSave?.cancel()
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// How a row's time reads: "now", "5m", "2h", then the weekday within a week, then the date.
@MainActor
enum NotificationTimeText {
    static func text(for date: Date, now: Date = Date(), locale: Locale, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 {
            return LocalizationManager.shared.string("now")
        }
        if seconds < 24 * 3600 {
            let formatter = DateComponentsFormatter()
            var cal = calendar
            cal.locale = locale
            formatter.calendar = cal
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = seconds < 3600 ? [.minute] : [.hour]
            return formatter.string(from: seconds) ?? ""
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        if seconds < 6 * 24 * 3600 {
            return date.formatted(style.weekday(.abbreviated))
        }
        return date.formatted(style.day().month(.abbreviated))
    }
}
