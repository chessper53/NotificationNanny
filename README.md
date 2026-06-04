# NotificationNanny

**Your macOS notification manager.** Control where banners appear, how they look, which apps get which treatment, and when they show up.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

<div align="center">
  <img width="340" alt="NotificationNanny popup" src="https://github.com/user-attachments/assets/65a9d5d5-24df-4e58-a657-389299c95ca2" />
  <img width="240" alt="NotificationNanny per-app rules" src="https://github.com/user-attachments/assets/9652aecb-5616-47ea-9078-bcde3c407052" />
</div>

## Settings

<table>
  <tr>
    <td align="center"><img src="PLACEHOLDER_POSITION" width="260" alt="Position"/><br/><sub>Position</sub></td>
    <td align="center"><img src="PLACEHOLDER_BANNER" width="260" alt="Banner"/><br/><sub>Banner</sub></td>
    <td align="center"><img src="PLACEHOLDER_EXCEPTIONS" width="260" alt="Exceptions"/><br/><sub>Exceptions</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="PLACEHOLDER_PRESETS" width="260" alt="Presets"/><br/><sub>Presets</sub></td>
    <td align="center"><img src="PLACEHOLDER_GENERAL" width="260" alt="General"/><br/><sub>General</sub></td>
    <td align="center"><img src="PLACEHOLDER_BACKUP" width="260" alt="Backup"/><br/><sub>Backup</sub></td>
  </tr>
</table>

## What it does

macOS gives you one place for notification banners and no way to change it. NotificationNanny takes that control back.

- Put banners wherever you want on any screen
- Scale them up or down, or replace the system banner entirely with a custom styled one
- Give specific apps their own rules: different position, different display, different banner style
- Hold banners until your display wakes up so nothing disappears while you are away
- Auto-dismiss banners on a timer, or leave them until you are ready

## Features

**Position**
- Drag the indicator on the screen preview, or use offset sliders for pixel-perfect placement
- Nine anchor points: corners, edges, center
- Independent position settings per physical display
- Force all banners to a specific screen regardless of where they originate

**Banner style**
- Scale notification text up or down; the slider snaps to 100% to return to the native macOS banner
- At any scale other than 100% NotificationNanny shows its own custom banner: app icon, sender, message, timestamp, a dismiss button, and a Show button on hover
- Per-group banner type: always native, always custom overlay, or let the scale decide

**Per-app rules**
- Group apps together and give each group its own position, display, banner type, and scale
- Apps not in any group use the global defaults
- Test each group with a sample notification straight from the settings

**Behaviour**
- Auto-dismiss: clear banners automatically after a configurable number of seconds
- Hold while display is asleep: queue notifications that arrive during sleep and show them on wake, with dismiss timers restarting fresh
- Pause while screen sharing: suppress all repositioning during screen capture sessions
- Don't move Notification Center: avoid touching the NC panel when you open it by clicking the clock

**Organisation**
- Presets: save and switch named configurations covering position, scale, and auto-dismiss
- Backup and restore: export all settings to JSON and import on another Mac

## Issues and feature requests

Open an issue. I read them all and work through them when I can. I have a full-time job so responses may take a little while, but nothing goes unread. [Open an issue here](https://github.com/chessper53/NotificationNanny/issues).

## Installation

```sh
brew tap chessper53/notificationnanny https://github.com/chessper53/NotificationNanny
brew install --cask notificationnanny
```

```sh
brew upgrade --cask notificationnanny   # to update
```

After installing, click the bell in your menu bar and hit **Grant Accessibility Permission** to get started.

## How it works

NotificationNanny uses the macOS Accessibility API to observe the notification center process. When a banner appears it repositions or replaces it according to your rules. For scaled or custom banners it intercepts the notification, moves the system banner off-screen, and shows its own window matching the macOS banner style. This relies on private internals, so Apple can change the behaviour in any OS update. The app sandbox is disabled because cross-process Accessibility access requires it.

## Privacy

No data is collected, transmitted, or stored outside your device. The Accessibility permission is used solely to observe and control notification windows on your local machine.

---

<details>
<summary>Full feature list and tags</summary>

### Features

- Drag-to-position tile: place notification banners anywhere on screen with a miniature display preview
- Pixel-perfect fine-tuning with horizontal and vertical offset sliders
- Nine anchor positions: corners, edges, center
- Multi-display support: independent position settings per physical screen, with a screen-force override per group
- Banner scale: resize notifications up or down; snaps to 100% (native macOS) with a magnetic slider
- Custom banner: replaces the system banner with a styled window showing app icon, sender, message, timestamp, dismiss button, and Show button on hover
- Per-group banner type: native (macOS system), custom overlay, or auto (follow scale setting)
- Per-app exceptions: group apps and give each group its own position, display, banner type, and scale
- Auto-dismiss: clear banners automatically after a configurable number of seconds
- Hold while display is asleep: queue banners that arrive during sleep and show them on wake with a fresh dismiss timer
- Pause while screen sharing: suppress repositioning during screen capture sessions
- Don't move Notification Center: skip repositioning when the NC settings panel is focused
- Presets: save and switch named configurations covering position, scale, and auto-dismiss
- Backup and restore: export all settings to JSON and import on another Mac
- Context-aware test notification: fires a sample banner using the currently active rule
- App name memory: known apps saved to disk and survive reinstalls
- Launch at login via SMAppService
- Enable/disable toggle to suspend all customisation without changing any settings
- Automatic Accessibility permission reset on binary update so Homebrew upgrades prompt cleanly
- Works on macOS 14 Sonoma and later, including macOS 26 Tahoe

### Tags

`macos` `menu-bar` `menubar-app` `status-bar` `tray-app` `notifications` `notification-banner` `notification-center` `notification-manager` `notification-position` `notification-placement` `notification-customization` `accessibility` `ax-api` `axuielement` `ax-observer` `swiftui` `swift` `swift-package-manager` `appkit` `combine` `macos-app` `mac-utility` `macos-utility` `productivity` `utility` `customization` `window-management` `multi-monitor` `multiple-displays` `open-source` `no-telemetry` `no-subscription` `lightweight` `native` `homebrew` `homebrew-cask` `macos-14` `macos-15` `macos-26` `sonoma` `sequoia` `tahoe`

</details>
