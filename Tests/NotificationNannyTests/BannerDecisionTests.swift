import Foundation
import Testing
@testable import NotificationNannyCore

/// Covers the custom-vs-native decision tree and the per-group "effective" value
/// resolution in `AppSettings` — the logic that drives whether a banner is
/// repositioned natively or replaced with the custom overlay.
@Suite("Banner decision") @MainActor
struct BannerDecisionTests {

    private func makeSettings() -> AppSettings {
        let name = "NotificationNannyTests_\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        return AppSettings(defaults: ud, knownAppsFileURL: tempURL)
    }

    /// Adds a group containing `app` and lets the caller mutate it in place.
    @discardableResult
    private func addGroup(_ s: AppSettings, app: String, _ mutate: (inout AppGroup) -> Void) -> UUID {
        let id = s.addGroup(name: "G")
        s.addApp(app, toGroup: id)
        let i = s.appGroups.firstIndex { $0.id == id }!
        mutate(&s.appGroups[i])
        return id
    }

    // MARK: - Global defaults

    @Test func defaults_useNativeBanner() {
        let s = makeSettings()
        #expect(s.shouldUseCustomBanner(for: "Mail") == false)
        #expect(s.shouldUseCustomBanner(for: nil) == false)
    }

    @Test func globalScale_activatesCustom() {
        let s = makeSettings()
        s.bannerScale = 1.5
        #expect(s.shouldUseCustomBanner(for: "Mail") == true)
    }

    @Test func globalScale_backToOne_isNative() {
        let s = makeSettings()
        s.bannerScale = 1.0
        #expect(s.shouldUseCustomBanner(for: "Mail") == false)
    }

    @Test func globalTint_activatesCustom() {
        let s = makeSettings()
        s.bannerTint = BannerTint(r: 1, g: 0, b: 0)
        #expect(s.shouldUseCustomBanner(for: "Mail") == true)
    }

    @Test func globalAnimation_activatesCustom() {
        let s = makeSettings()
        s.bannerAnimation = .bounce
        #expect(s.shouldUseCustomBanner(for: "Mail") == true)
    }

    // MARK: - Per-group overrides

    @Test func groupModeNative_forcesNative_evenWithScale() {
        let s = makeSettings()
        s.bannerScale = 2.0   // global would otherwise force custom
        addGroup(s, app: "Slack") { $0.bannerMode = .native }
        #expect(s.shouldUseCustomBanner(for: "Slack") == false)
    }

    @Test func groupModeCustom_forcesCustom_atScaleOne() {
        let s = makeSettings()
        addGroup(s, app: "Slack") { $0.bannerMode = .custom }
        #expect(s.shouldUseCustomBanner(for: "Slack") == true)
    }

    @Test func groupScaleOverride_activatesCustom() {
        let s = makeSettings()
        addGroup(s, app: "Slack") { $0.bannerScale = 1.75 }
        #expect(s.shouldUseCustomBanner(for: "Slack") == true)
    }

    @Test func groupAnimationOverride_activatesCustom() {
        let s = makeSettings()
        addGroup(s, app: "Slack") { $0.bannerAnimation = .fade }
        #expect(s.shouldUseCustomBanner(for: "Slack") == true)
    }

    @Test func groupTint_activatesCustom() {
        let s = makeSettings()
        addGroup(s, app: "Slack") { $0.bannerTint = BannerTint(r: 0, g: 0, b: 1) }
        #expect(s.shouldUseCustomBanner(for: "Slack") == true)
    }

    // MARK: - Effective value resolution (override vs inherit)

    @Test func effectiveScale_inheritsGlobalWhenGroupNil() {
        let s = makeSettings()
        s.bannerScale = 1.3
        addGroup(s, app: "Slack") { _ in }   // no scale override
        #expect(s.effectiveBannerScale(for: "Slack") == 1.3)
    }

    @Test func effectiveScale_usesGroupOverride() {
        let s = makeSettings()
        s.bannerScale = 1.3
        addGroup(s, app: "Slack") { $0.bannerScale = 2.0 }
        #expect(s.effectiveBannerScale(for: "Slack") == 2.0)
    }

    @Test func effectiveAnimation_inheritsGlobalWhenGroupNil() {
        let s = makeSettings()
        s.bannerAnimation = .scale
        addGroup(s, app: "Slack") { _ in }
        #expect(s.effectiveBannerAnimation(for: "Slack") == .scale)
    }

    @Test func effectiveAnimation_usesGroupOverride() {
        let s = makeSettings()
        s.bannerAnimation = .scale
        addGroup(s, app: "Slack") { $0.bannerAnimation = .bounce }
        #expect(s.effectiveBannerAnimation(for: "Slack") == .bounce)
    }

    @Test func effectiveMode_nilWhenUnset() {
        let s = makeSettings()
        addGroup(s, app: "Slack") { _ in }
        #expect(s.effectiveBannerMode(for: "Slack") == nil)
    }

    @Test func appNotInGroup_usesGlobalDecision() {
        let s = makeSettings()
        addGroup(s, app: "Slack") { $0.bannerMode = .custom }
        // A different app inherits global (native by default).
        #expect(s.shouldUseCustomBanner(for: "Mail") == false)
    }

    // MARK: - GroupID variants mirror the appName variants

    @Test func byGroupID_matchesByAppName() {
        let s = makeSettings()
        let id = addGroup(s, app: "Slack") { $0.bannerScale = 1.6 }
        #expect(s.shouldUseCustomBanner(forGroupID: id) == s.shouldUseCustomBanner(for: "Slack"))
        #expect(s.effectiveBannerScale(forGroupID: id) == 1.6)
    }
}
