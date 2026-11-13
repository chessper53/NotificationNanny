import Testing
@testable import NotificationNannyCore

/// A notification's text never goes into the log outside lab runs: only its length.
@Suite("Log privacy")
struct LogPrivacyTests {
    @Test func textBecomesItsLength() {
        guard !LogPrivacy.showsText else { return }
        let secret = "Your code is 482913"
        let logged = LogPrivacy.describe(secret)
        #expect(!logged.contains("482913"))
        #expect(logged == "<\(secret.count) chars>")
    }
}
