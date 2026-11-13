import Foundation
import Testing
@testable import NotificationNannyCore

@Suite("cleanAXString")
struct AXStringTests {

    @Test func plainString_unchanged() {
        #expect(cleanAXString("Slack") == "Slack")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(cleanAXString("  Messages  ") == "Messages")
    }

    @Test func stripsLeftToRightMark() {
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
        #expect(cleanAXString("Lastname, First") == "Lastname, First")
    }
}
