import Foundation
import Testing
@testable import NotificationNannyCore

@MainActor
@Suite("Notification times")
struct NotificationTimesTests {

    @Test func arrival_isKeptFromTheFirstSighting() {
        let times = NotificationTimes(fileURL: nil)
        let first = Date(timeIntervalSince1970: 1000)
        times.noteArrival("a", at: first)
        times.noteArrival("a", at: first.addingTimeInterval(60))
        #expect(times.arrival(of: "a") == first)
    }

    /// Already listed when first seen: it came in at some unknown moment, so no time is
    /// shown, and a later sighting doesn't turn it into a new arrival either.
    @Test func alreadyListed_hasNoTime_evenWhenSeenAgain() {
        let times = NotificationTimes(fileURL: nil)
        times.noteAlreadyListed("old")
        times.noteArrival("old")
        #expect(times.arrival(of: "old") == nil)
    }

    @Test func prune_dropsWhatTheListNoLongerHas() {
        let times = NotificationTimes(fileURL: nil)
        let now = Date()
        times.noteArrival("kept", at: now)
        times.noteArrival("gone", at: now)
        times.prune(keeping: ["kept"], now: now)
        #expect(times.arrival(of: "kept") == now)
        #expect(times.arrival(of: "gone") == nil)
    }

    @Test func prune_dropsTimesOlderThanAMonth() {
        let times = NotificationTimes(fileURL: nil)
        let now = Date()
        times.noteArrival("ancient", at: now.addingTimeInterval(-31 * 24 * 3600))
        times.prune(keeping: ["ancient"], now: now)
        #expect(times.arrival(of: "ancient") == nil)
    }

    @Test func savedTimes_loadAgain() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("times-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let date = Date(timeIntervalSince1970: 5000)
        let times = NotificationTimes(fileURL: url)
        times.noteArrival("a", at: date)
        times.noteAlreadyListed("b")
        times.flush()
        let loaded = NotificationTimes(fileURL: url)
        #expect(loaded.arrival(of: "a") == date)
        loaded.noteArrival("b")
        #expect(loaded.arrival(of: "b") == nil)
    }

    @Test func text_minutesHoursWeekdayDate() {
        let en = Locale(identifier: "en_US")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_900_000) // a Sunday afternoon, UTC
        func text(_ ago: TimeInterval) -> String {
            NotificationTimeText.text(for: now.addingTimeInterval(-ago), now: now, locale: en, calendar: cal)
        }
        #expect(text(5) == LocalizationManager.shared.string("now"))
        #expect(text(5 * 60) == "5m")
        #expect(text(2 * 3600 + 100) == "2h")
        #expect(text(2 * 24 * 3600) == "Fri")
        #expect(text(20 * 24 * 3600).contains("Oct"))
    }
}
