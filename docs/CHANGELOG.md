# Changelog

All notable changes to NotificationNanny are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [7.7.0] — 2026-08-10

### Added
- **Custom banner text color** — a global override for the custom renderer's text (title, body, app name, timestamp). Leaving it unset keeps text on the system's adaptive `.primary`/`.secondary`/`.tertiary` styles rather than a fixed color, so it stays legible against the banner's own light/dark-adaptive background (see the Fixed entry below). Configurable from the Banner tab next to Background Color.
- Universal (arm64 + x86_64) release builds — the release workflow now builds with `UNIVERSAL=1` and verifies both architectures are present with `lipo` before packaging, so Intel Macs installing via Homebrew get a binary that actually launches. (Previously, only arm64 was shipped; Intel installs failed with "unsupported.") Building a universal artifact requires full Xcode (not Command Line Tools) — see `docs/RELEASING.md`.

### Fixed
- **Persistent-style notifications not repositioned** — macOS renders "Persistent" notification style (System Settings → Notifications → app → Notification style) with the `AXNotificationCenterAlert`/`AlertStack` accessibility subrole instead of the `AXNotificationCenterBanner`/`BannerStack` subrole used by "Temporary" style. NotificationNanny only recognized the Banner subroles, so Persistent notifications were never identified as banners — the app name couldn't be resolved, the readiness gate never passed, and after retries were exhausted the notification was left exactly where macOS natively placed it (not the cursor's screen, not the user's configured position). Both Alert subroles are now recognized.
- **Custom banner color mismatch on non-default animations** — picking any banner animation other than Default forces the custom-overlay rendering path even with no tint set. That overlay forced a `.darkAqua` appearance and painted a flat black overlay to approximate the native banner's look — correct-looking only when the system happened to already be in Dark Mode. In Light Mode, picking an animation swapped a light native banner for a dark custom one. The overlay's background now inherits the system's actual current appearance instead of a hardcoded approximation.
- `depends_on macos: ">= :sonoma"` in the Homebrew cask used a deprecated string-comparison form, printing a verbose warning on every `brew` invocation involving the tap. Changed to the plain-symbol form (`depends_on macos: :sonoma`), same minimum-version meaning.

### Changed
- `NotificationNannyCore`'s 31 source files, previously flat, are now grouped into `Engine/`, `Models/`, `UI/{SettingsView,MenuBar,Overlay}/`, `System/`, and `Diagnostics/` (file moves only — no logic changes). See `docs/ARCHITECTURE.md` for the updated module map.
- Two previously silent skip paths (an unrecognized-subrole large NC window, and readiness-gate exhaustion) now log a user-visible reason including the AX subrole, so a future diagnostics paste can distinguish "genuinely not a banner" from "a subrole we don't recognize yet" without needing a live repro. The readiness-gate log also reports elapsed time since the last display wake / screen-configuration-change event, to help tell a recognition gap apart from an AX-service warm-up timing issue.

## [7.6.1] — 2026-07-17

### Fixed
- **Saved position silently reverting to the default corner** — per-screen placements and the forced-display override were keyed by the raw `CGDirectDisplayID`, which macOS can reassign to the same physical monitor across sleep/wake or a dock reconnect. When that happened the saved entry was orphaned and lookups fell back to the default position. Placements and display overrides are now keyed by a persistent per-monitor identifier (`CGDisplayCreateUUIDFromDisplayID`) that survives those reassignments, with a one-time migration of existing settings.
- **Dismissing a custom banner revealed the native notification underneath** — the custom overlay only parked the real Notification Center banner off-screen under a few short-lived holds, so once the overlay was closed (✕, tap-to-open, or auto-dismiss) the native banner popped back into view. Dismissing the overlay now retires the underlying banner too.

### Added
- Display-topology logging (`Display`-tagged) on every screen-configuration change and wake — records each connected display's ID and stable key so a diagnostics report reveals whether macOS reassigned a monitor's display ID, and a one-time log line when legacy settings are migrated to the stable keys.

### Changed
- `didChangeScreenParametersNotification` handling is now debounced, collapsing the 2–3 events macOS fires per topology change into a single repositioning sweep against the settled layout.

## [7.6.0] — 2026-06-26

### Added
- **Apply a report** (Diagnostics → Developer) — paste a diagnostics report and the app takes over the settings it describes (default position, behavior toggles, auto-dismiss, banner scale) for local reproduction of a user's configuration.
- Diagnostics report now includes the user's **default position** and a **Behavior** summary of every key toggle (`protectDesktopWidgets`, `holdWhileAsleep`, `avoidNCPanel`, `followActiveScreen`, `pauseWhileStreaming`, `pauseDuringFocus`), so bug reports state up front whether a given path is even active.
- User-visible (`Widget`-tagged) logging when desktop widgets are protected, when a display-sleep park leaves them in place, and when the safety net refuses to park one.

### Changed
- Simplified the Diagnostics tab to a single **Copy Diagnostics** action (settings + system info + activity log in one paste); moved the activity log and edge-case tools under a collapsed **Developer** section.

### Fixed
- **Desktop widgets disappearing after display sleep** — `handleDisplaySleep` parked every Notification Center window off-screen, including desktop widgets, which the wake path then refused to restore (the widget-protection guard skips them), stranding them until the widget shelf was re-edited. Sleep now leaves protected widgets in place.
- **Notification Center panel replaced by a stale custom banner** — with "don't move Notification Center" off, the panel was rendered through the custom-overlay path and showed the last notification instead of the real panel. The panel now always uses the native move path, so it appears genuinely at the configured position.
- Added a central guard so no off-screen park can ever strand a protected widget, regardless of code path.

## [7.5.0] — 2026-06-18

### Added
- **Pause during Focus / Do Not Disturb** — optional toggle (General tab) that leaves banners untouched while any macOS Focus mode is active. Backed by `FocusModeMonitor`, which reads the Focus assertion store and caches the result (1s) so the hot reposition path stays cheap.
- **Don't move desktop widgets** — new toggle (default on) that detects widget/NC-chrome windows (small windows with no banner subrole) and leaves them where the user placed them instead of repositioning them.

### Changed
- Backup/restore export now carries the `protectDesktopWidgets` and `pauseDuringFocus` toggles. Both decode as optional, so older backups still import cleanly (absent values fall back to defaults).
- Extracted the log-entry row into its own `LogEntryRow` view; expanded notification testing/debugging tools in the Diagnostics tab.

## [7.3.x] — 2026-06-10 → 2026-06-17

### Added
- **Snooze / pause for N minutes** — temporarily suspend all repositioning with an auto-resume timer; surfaced in the menu bar and the Diagnostics report.
- Export schema versioning (`schemaVersion`) for future-proof backups.
- Diagnostics tab consolidating health checks, the activity log, and edge-case tools (AX-tree dump, back-to-back burst test); "Report a bug" auto-attaches diagnostics.

### Changed
- AX primitives extracted to an `AXUIElement` extension (`AXSupport.swift`), shared by the repositioner and `AppNameResolver`.

### Fixed
- Cluster of back-to-back / rapid-notification races: per-window generation counter, test-banner identity, readiness gate ("second message wasn't custom"), overlay content refresh, and a transient width clamp.
- Title/body extraction now uses `AXStaticText` children (handles commas in sender names and wrapped bodies).
- Screen-reconfiguration handling re-evaluates banners on display connect/disconnect/mirror.

## [7.0.0 – 7.2.1] — 2026-06-01 → 2026-06-05

### Added
- **Banner tint** — overlay any color on the banner background (presets or full color picker).
- **Appear animations** — Default, Slide, Bounce, Fade, Scale; selectable globally and per group.
- Per-group banner color independent of the global tint; per-group test button.

### Changed
- `SettingsView` split into eight per-tab view files.
- `BannerTint` value type replaces the `bannerColorR/G/B` optional triple.
- `PrivateWindowAPI` namespace isolates all private CGS/SkyLight SPI; dead scale-gauntlet code removed.

## [6.x] — 2026-05-07 → 2026-06-01

### Added
- Per-app rules (Exceptions): named groups with their own position, display, banner mode, scale, and tint.
- Per-exception screen selection; in-app Homebrew auto-updater with live output; update checker.
- App-icon display, banner stacking, pause-while-screen-sharing, hold-while-display-asleep.
- Accessibility permission monitoring; injectable settings via `NotificationSettingsProviding`.

## [3.0.0 – 5.0.0] — 2026-05-07

### Added
- Presets: save and recall named configurations (up to 5).
- Notification stacking for multiple simultaneous banners.

### Changed
- Removed global hotkeys; fixed a launch hang.

## [0.1.0 – 2.1.0]

Initial public releases: menu-bar app that repositions macOS notification banners to a
user-chosen anchor on any display via the Accessibility API.

[7.6.1]: https://github.com/chessper53/NotificationNanny/releases/latest
[7.3.x]: https://github.com/chessper53/NotificationNanny/releases
[7.0.0 – 7.2.1]: https://github.com/chessper53/NotificationNanny/releases
[6.x]: https://github.com/chessper53/NotificationNanny/releases
[3.0.0 – 5.0.0]: https://github.com/chessper53/NotificationNanny/releases
[0.1.0 – 2.1.0]: https://github.com/chessper53/NotificationNanny/releases
