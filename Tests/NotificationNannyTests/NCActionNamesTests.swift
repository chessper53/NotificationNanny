import Foundation
import Testing
@testable import NotificationNannyCore

/// Banners are closed through their Close or Clear All action, whose names macOS
/// translates. A banner on French macOS offers Fermer, not Close.
@Suite("NCActionNames")
struct NCActionNamesTests {

    @Test func customActionName_readsTheNameLine() {
        #expect(customActionName("Name:Close\nTarget:0x0\nSelector:(null)") == "Close")
        #expect(customActionName("Name:Tout effacer\nTarget:0x0\nSelector:(null)") == "Tout effacer")
    }

    @Test func customActionName_keepsAStandardAction() {
        #expect(customActionName("AXPress") == "AXPress")
    }

    @Test func translations_collectEveryLanguage() {
        let table: [String: Any] = [
            "LocProvenance": ["en": "1"],
            "en": ["Close": "Close", "Clear All": "Clear All"],
            "fr": ["Close": "Fermer", "Clear All": "Tout effacer"],
            "de": ["Close": "Schließen"],
        ]
        #expect(NCActionNames.translations(of: "Close", in: table) == ["Close", "Fermer", "Schließen"])
        #expect(NCActionNames.translations(of: "Clear All", in: table) == ["Clear All", "Tout effacer"])
    }

    @Test func translations_keepEnglishWithoutATable() {
        #expect(NCActionNames.translations(of: "Close", in: [:]) == ["Close"])
    }

    /// Reads the real table of this Mac's Notification Center.
    @MainActor @Test func systemTable_hasFrench() {
        #expect(NCActionNames.close.isSuperset(of: ["Close", "Fermer"]))
        #expect(NCActionNames.clearAll.isSuperset(of: ["Clear All", "Tout effacer"]))
    }
}
