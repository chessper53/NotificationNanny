import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("Logger") @MainActor
struct NannyLoggerTests {
    /// The same line again within a minute is counted, not kept: told as one line once
    /// something else is logged.
    @Test func repeatsCollapse() {
        let log = NannyLogger()
        for _ in 1...3 { log.log("Notification Center isn't answering", level: .warn, tag: "AX") }
        log.log("something else", tag: "AX")
        let lines = log.exportText().split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasSuffix("Notification Center isn't answering"))
        #expect(lines[1].contains("the same 2 more times"))
        #expect(lines[2].hasSuffix("something else"))
    }

    /// Repeats still being counted show in an export made meanwhile.
    @Test func repeatsSoFarShowInAnExport() {
        let log = NannyLogger()
        log.log("x"); log.log("x")
        #expect(log.exportText().contains("1 more time so far"))
    }

    /// Debug detail is in the live log, never in what is saved or reported.
    @Test func debugStaysOutOfExports() {
        let log = NannyLogger()
        log.log("routine", level: .debug, tag: "AX")
        log.log("kept", tag: "AX")
        #expect(log.entries.count == 2)
        #expect(!log.exportText().contains("routine"))
    }

    /// Lines that differ only in a number tell different things apart: all kept.
    @Test func differentNumbersAreDifferentLines() {
        let log = NannyLogger()
        log.log("Teams → topCenter, pos (12, -34)"); log.log("Teams → topCenter, pos (900, -34)")
        #expect(log.exportText().split(separator: "\n").count == 2)
    }
}
