import Foundation
import Testing
@testable import NotificationNannyCore

/// `cleanAXString` strips default-ignorable scalars (notably the U+200E mark that
/// apps like WhatsApp inject into accessibility strings) and trims whitespace.
/// Banner app-name / title extraction depends on this being correct.
@Suite("cleanAXString")
struct AXStringTests {

    @Test func plainString_unchanged() {
        #expect(cleanAXString("Slack") == "Slack")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(cleanAXString("  Messages  ") == "Messages")
    }

    @Test func stripsLeftToRightMark() {
        // U+200E is default-ignorable; it must be removed.
        #expect(cleanAXString("WhatsApp\u{200E}") == "WhatsApp")
        #expect(cleanAXString("\u{200E}John Doe") == "John Doe")
    }

    @Test func stripsMarksAndTrims_combined() {
        #expect(cleanAXString("\u{200E}  Hi there \u{200F}") == "Hi there")
    }

    @Test func emptyStays_empty() {
        #expect(cleanAXString("") == "")
    }

    @Test func onlyIgnorableScalars_becomeEmpty() {
        #expect(cleanAXString("\u{200E}\u{200F}") == "")
    }

    @Test func keepsInternalPunctuationAndCommas() {
        // Sender names with commas must survive (the title/body split handles them).
        #expect(cleanAXString("Lastname, First") == "Lastname, First")
    }
}
