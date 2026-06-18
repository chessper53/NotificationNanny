# Changelog

All notable changes to NotificationNanny are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[7.5.0]: https://github.com/chessper53/NotificationNanny/releases/latest
[7.3.x]: https://github.com/chessper53/NotificationNanny/releases
[7.0.0 – 7.2.1]: https://github.com/chessper53/NotificationNanny/releases
[6.x]: https://github.com/chessper53/NotificationNanny/releases
[3.0.0 – 5.0.0]: https://github.com/chessper53/NotificationNanny/releases
[0.1.0 – 2.1.0]: https://github.com/chessper53/NotificationNanny/releases
