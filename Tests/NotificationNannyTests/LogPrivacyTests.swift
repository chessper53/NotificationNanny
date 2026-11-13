import Testing
@testable import NotificationNannyCore

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
