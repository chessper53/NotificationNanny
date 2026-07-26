# Global Banner Text Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users set one global custom text color for custom notification banners while retaining white as the default.

**Architecture:** Store an optional global `BannerTint` override in `AppSettings`; its absence resolves to white and leaves native banners untouched. A present override turns on the custom-banner path, which passes the resolved color through `NotificationRepositioner` and `CustomBannerManager` into the overlay and its settings preview.

**Tech Stack:** Swift, SwiftUI, AppKit, UserDefaults, Swift Testing.

---

### Task 1: Add a tested global text-color setting

**Files:**
- Modify: `Tests/NotificationNannyTests/AppSettingsTests.swift`
- Modify: `Sources/NotificationNannyCore/AppSettings.swift`

- [ ] **Step 1: Write failing setting tests**

Append these tests to `AppSettingsTests`:

```swift
@Test func bannerTextTint_defaultsToWhiteWithoutOverride() {
    let (settings, _) = makeSettings()
    #expect(settings.bannerTextTint == nil)
}

@Test func bannerTextTint_persistsAcrossSettingsInstances() {
    let (settings, suiteName) = makeSettings()
    let tint = BannerTint(r: 0.2, g: 0.4, b: 0.6)
    settings.bannerTextTint = tint

    let defaults = UserDefaults(suiteName: suiteName)!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(suiteName)-restored.json")
    let restored = AppSettings(defaults: defaults, knownAppsFileURL: url)
    #expect(restored.bannerTextTint == tint)
}

@Test func customTextTint_activatesCustomBanner() {
    let (settings, _) = makeSettings()
    #expect(!settings.shouldUseCustomBanner(for: nil))

    settings.bannerTextTint = BannerTint(r: 1.0, g: 0.3, b: 0.2)
    #expect(settings.shouldUseCustomBanner(for: nil))

    settings.clearBannerTextColor()
    #expect(!settings.shouldUseCustomBanner(for: nil))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AppSettings`

Expected: compilation failure because `bannerTextTint` and `clearBannerTextColor()` do not exist.

- [ ] **Step 3: Implement persisted global override**

In `AppSettings.Key`, add `bannerTextColorR`, `bannerTextColorG`, `bannerTextColorB`, and `hasBannerTextColor`. Add matching published RGB storage plus a `hasBannerTextColor` flag, initialize them from `UserDefaults`, and provide:

```swift
package var bannerTextTint: BannerTint? { get set }
package var effectiveBannerTextColor: Color { bannerTextTint?.color ?? .white }
package func clearBannerTextColor() { bannerTextTint = nil }
```

The setter stores RGB values and the presence flag; clearing resets the three RGB values to zero and clears the flag. Extend `shouldUseCustomBannerImpl` so `hasBannerTextColor` returns `true` when no explicit native banner mode is selected.

- [ ] **Step 4: Run the setting tests to verify they pass**

Run: `swift test --filter AppSettings`

Expected: all `AppSettings` tests pass, including the three new text-color cases.

### Task 2: Render and configure the chosen color

**Files:**
- Modify: `Sources/NotificationNannyCore/CustomOverlay.swift`
- Modify: `Sources/NotificationNannyCore/NotificationRepositioner.swift:974-987`
- Modify: `Sources/NotificationNannyCore/SettingsView+BannerTab.swift:64-119`

- [ ] **Step 1: Pass the effective color through the overlay boundary**

Add a `textColor: Color` argument to `CustomBannerManager.showBanner` and `CustomBannerView`. At the call site in `NotificationRepositioner`, pass `settings.effectiveBannerTextColor` together with the existing effective background color.

- [ ] **Step 2: Apply visual hierarchy in `CustomBannerView`**

Replace the three text foreground styles with these expressions:

```swift
Text(content.appName.uppercased()).foregroundStyle(textColor.opacity(0.65))
Text("now").foregroundStyle(textColor.opacity(0.55))
Text(content.title).foregroundStyle(textColor)
Text(content.body).foregroundStyle(textColor.opacity(0.85))
```

Keep the close button and icon foreground styles unchanged.

- [ ] **Step 3: Add the global Text Color card and preview input**

Insert a Banner-tab card after `Background Color`. Bind its `ColorPicker` to
`settings.bannerTextTint?.color ?? .white`; convert the selected color through
`NSColor(...).usingColorSpace(.sRGB)` and write `BannerTint(r:g:b:)`. Its Reset
button calls `settings.clearBannerTextColor()` and is disabled when
`hasBannerTextColor` is false.

Add `textColor: Color` to `AnimationPreviewPane`, pass
`settings.effectiveBannerTextColor` at its call site, and draw the two sample
text bars with `textColor.opacity(0.85)` and `textColor.opacity(0.55)`.

- [ ] **Step 4: Build and run the complete test suite**

Run: `swift test`

Expected: exit status 0 with all tests passing.

- [ ] **Step 5: Manually verify the overlay**

Run: `UNIVERSAL=1 ./build-app.sh --run`

Expected: after choosing a non-white Text Color in Banner settings and pressing
`Send Test Notification`, the custom overlay uses the chosen title color, a
softer body color, and dimmer app-name/timestamp text. Press Reset and confirm
the custom override clears and white is restored for custom overlays.

- [ ] **Step 6: Commit the implementation**

Run:

```bash
git add Sources/NotificationNannyCore/AppSettings.swift \
        Sources/NotificationNannyCore/CustomOverlay.swift \
        Sources/NotificationNannyCore/NotificationRepositioner.swift \
        Sources/NotificationNannyCore/SettingsView+BannerTab.swift \
        Tests/NotificationNannyTests/AppSettingsTests.swift
git commit -m "feat: add global banner text color"
```

Expected: one commit that implements and tests global custom-banner text color.
