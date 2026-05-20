# NotificationNanny

A macOS menu-bar app that moves notification banners wherever you want them, to any custom position on any of your displays.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

<img width="366" alt="NotificationNanny panel" src="https://github.com/user-attachments/assets/8e315785-589c-4a41-9714-325dc6d42dd9" />

## Features

- **Drag-to-position.** Move the purple chip around the screen tile, or use the sliders for pixel-perfect placement.
- **Per-app rules.** Different position for different apps, e.g. Teams bottom-left, Calendar top-center, everything else top-right.
- **Multi-display.** Independent settings per screen, with an option to force all banners to one display.
- **Auto-dismiss.** Slide banners off-screen automatically after a configurable number of seconds.
- **Presets.** Save and switch between named configurations.

## Installation

```sh
brew tap chessper53/notificationnanny https://github.com/chessper53/NotificationNanny
brew install --cask notificationnanny
```

```sh
brew upgrade --cask notificationnanny   # to update
```

After installing, click the bell in your menu bar and hit **Grant Accessibility Permission** to get started.

## Issues and feature requests

Open an issue. I read them and act on them. If something is broken, behaving unexpectedly, or you want a feature that isn't there, [open an issue](https://github.com/chessper53/NotificationNanny/issues) and I'll pick it up.

## How it works

NotificationNanny uses the macOS Accessibility API to attach to the notification center process and reposition banner windows as they appear. This relies on undocumented internals, so Apple can break it in any OS update without notice. The app sandbox is disabled because cross-process Accessibility access requires it.

## Privacy

No data is collected, transmitted, or stored. The Accessibility permission is used solely to reposition notification windows on your local machine.

---

<details>
<summary>Full feature list &amp; tags</summary>

### Features

- Drag-to-position tile: place notification banners anywhere on screen with a miniature display preview
- Pixel-perfect fine-tuning with horizontal and vertical offset sliders
- Per-app rules: assign apps to named groups, each with its own position — e.g. Teams bottom-left, Calendar top-center, everything else top-right
- Multi-display support: independent position settings per physical screen, with a screen-force override
- Auto-dismiss: automatically slide banners off-screen after a configurable number of seconds
- Presets: save and switch between named position configurations
- Context-aware test notification: fires a sample banner using the currently selected rule's placement
- App name memory: known apps saved to disk and survive reinstalls
- Launch at login support via SMAppService
- Enable/disable toggle to suspend all repositioning without changing any settings
- Automatic Accessibility permission reset on binary update so Homebrew upgrades prompt cleanly
- Works on macOS 14 Sonoma and later, including macOS 26 Tahoe

### Tags

`macos` `menu-bar` `menubar-app` `status-bar` `tray-app` `notifications` `notification-banner` `notification-center` `notification-manager` `notification-position` `notification-placement` `accessibility` `ax-api` `axuielement` `ax-observer` `swiftui` `swift` `swift-package-manager` `appkit` `combine` `macos-app` `mac-utility` `macos-utility` `productivity` `utility` `customization` `window-management` `multi-monitor` `multiple-displays` `open-source` `no-telemetry` `no-subscription` `lightweight` `native` `homebrew` `homebrew-cask` `macos-14` `macos-15` `macos-26` `sonoma` `sequoia` `tahoe`

</details>
