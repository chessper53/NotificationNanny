import Foundation
import Testing
@testable import NotificationNannyCore

/// When NN quits on its own, the crash report and the log of the session that crashed
/// are all there is to go on. These cover reading them back.
@Suite("Crash diagnostics")
struct CrashDiagnosticsTests {

    private static func ips(app: String = "NotificationNanny", timestamp: String = "2026-10-17 10:40:12.00 +0200") -> String {
        let header = #"{"app_name":"\#(app)","timestamp":"\#(timestamp)","app_version":"8.0.3","bug_type":"309","name":"\#(app)"}"#
        let body = #"""
        {
          "exception" : {"type" : "EXC_BREAKPOINT", "signal" : "SIGTRAP"},
          "asi" : {"libswiftCore.dylib" : ["Fatal error: Index out of range"]},
          "faultingThread" : 1,
          "threads" : [
            {"frames" : [{"imageOffset" : 10, "symbol" : "mach_msg", "imageIndex" : 1}]},
            {"frames" : [
              {"imageOffset" : 20, "symbol" : "_assertionFailure", "symbolLocation" : 4, "imageIndex" : 1},
              {"imageOffset" : 30, "symbol" : "NotificationRepositioner.sweep()", "symbolLocation" : 88,
               "imageIndex" : 0, "sourceFile" : "NotificationRepositioner.swift", "sourceLine" : 1032}
            ]}
          ],
          "usedImages" : [{"name" : "NotificationNanny"}, {"name" : "libswiftCore.dylib"}]
        }
        """#
        return header + "\n" + body
    }

    private static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func parsesTheCrashedFrameInOurOwnCode() throws {
        let crash = try #require(CrashReports.parse(Self.ips(), processName: "NotificationNanny", fallbackDate: .distantPast))
        #expect(crash.appVersion == "8.0.3")
        #expect(crash.exception == "EXC_BREAKPOINT (SIGTRAP)")
        #expect(crash.message == "Fatal error: Index out of range")
        #expect(crash.frame == "NotificationRepositioner.sweep() + 88 (NotificationRepositioner.swift:1032)")
        #expect(crash.date == Date(timeIntervalSince1970: 1_792_226_412))
    }

    @Test func ignoresOtherProcesses() {
        #expect(CrashReports.parse(Self.ips(app: "Google Chrome"), processName: "NotificationNanny", fallbackDate: .now) == nil)
    }

    @Test func ignoresGarbage() {
        #expect(CrashReports.parse("not a crash report", processName: "NotificationNanny", fallbackDate: .now) == nil)
    }

    @Test func latestPicksTheNewestOfOurReports() throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let write = { (name: String, text: String, age: TimeInterval) in
            let url = dir.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        try write("NotificationNanny-2026-10-10-090000.ips", Self.ips(timestamp: "2026-10-10 09:00:00.00 +0200"), 600)
        try write("NotificationNanny-2026-10-17-104012.ips", Self.ips(), 300)
        // Newer, but not ours.
        try write("ExcUserFault_NotificationNanny-2026-10-18-080000.ips", Self.ips(), 0)
        try write("Google Chrome-2026-10-18-080000.ips", Self.ips(app: "Google Chrome"), 0)

        let crash = try #require(CrashReports.latest(in: dir))
        #expect(crash.date == Date(timeIntervalSince1970: 1_792_226_412))
    }

    @Test func latestIsNilWithoutReports() {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(CrashReports.latest(in: dir) == nil)
        #expect(CrashReports.latest(in: dir.appendingPathComponent("missing")) == nil)
    }

    @MainActor @Test func onlyARecentCrashIsAWarning() {
        let now = Date()
        let crash = { (age: TimeInterval) in
            CrashSummary(date: now.addingTimeInterval(-age), appVersion: "8.0.3",
                         exception: "EXC_BREAKPOINT (SIGTRAP)", message: nil, frame: "f()")
        }
        #expect(Diagnostics.crashItem(nil, now: now).status == .ok)
        #expect(Diagnostics.crashItem(crash(3600), now: now).status == .warn)
        #expect(Diagnostics.crashItem(crash(30 * 24 * 3600), now: now).status == .info)
        #expect(Diagnostics.crashItem(crash(3600), now: now).detail.hasSuffix("v8.0.3, EXC_BREAKPOINT (SIGTRAP) in f()"))
    }

    @Test func eachLaunchMovesTheLastSessionAside() {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = SessionLogFile(directory: dir)
        first.append("first session")
        let second = SessionLogFile(directory: dir)
        second.append("second session")
        #expect(second.previousSession == "first session\n")
        _ = SessionLogFile(directory: dir)
        #expect(second.previousSession == "second session\n")
    }

    @Test func aFullFileStartsOverWithWhatItIsGiven() throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = SessionLogFile(directory: dir, maxBytes: 10)
        file.append("0123456789")
        #expect(file.isFull)
        file.replace(with: "tail")
        #expect(!file.isFull)
        #expect(try String(contentsOf: file.currentURL, encoding: .utf8) == "tail\n")
    }

    @MainActor @Test func logBeforeACrashInThePreviousSession() {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = NannyLogger()
        first.startWritingToDisk(in: dir)
        for i in 1...5 { first.log("line \(i)") }

        let second = NannyLogger()
        second.startWritingToDisk(in: dir)
        let crash = { (date: Date) in
            CrashSummary(date: date, appVersion: nil, exception: nil, message: nil, frame: nil)
        }
        let tail = second.logBefore(crash(Date()), maxLines: 2)
        #expect(tail?.hasSuffix("line 5") == true)
        #expect(tail?.contains("line 4") == true)
        #expect(tail?.contains("line 3") == false)
        // A crash from before that session belongs to some earlier run.
        #expect(second.logBefore(crash(.distantPast), maxLines: 2) == nil)
        #expect(second.logBefore(nil, maxLines: 2) == nil)
    }
}
