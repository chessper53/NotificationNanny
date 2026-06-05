# NotificationNanny

**Your macOS notification manager.** Control where banners appear, how they look, which apps get which treatment, and when they show up.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-7.0.0-brightgreen)

## Settings

<table>
  <tr>
    <td align="center"><img src="https://github.com/user-attachments/assets/777c81f7-6cc5-4407-a4b6-5328de2c262b" width="260" alt="Position"/><br/><sub>Position</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/5d01ec6a-8267-4114-9691-9b5b46f1e3cd" width="260" alt="Banner"/><br/><sub>Banner</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/366b1afc-c5a2-4deb-8837-5a4ca7794268" width="260" alt="Exceptions"/><br/><sub>Exceptions</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="https://github.com/user-attachments/assets/bd47b5e8-e667-4bb0-bf55-8ed1c15c9029" width="260" alt="Presets"/><br/><sub>Presets</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/f670ef93-8241-45e5-bef2-282506dd64d6" width="260" alt="General"/><br/><sub>General</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/c63fce84-d270-4e68-b711-f43190e393e5" width="260" alt="Help"/><br/><sub>Help</sub></td>
  </tr>
</table>

## What it does

macOS gives you one place for notification banners and no way to change it. NotificationNanny takes that control back.

- Put banners wherever you want on any screen
- Scale them up or down, tint them a color, or replace the system banner entirely with a custom styled one
- Give specific apps their own rules: different position, different display, different banner style
- Choose how banners animate in: system default, slide, bounce, fade, or scale
- Hold banners until your display wakes up so nothing disappears while you are away
- Auto-dismiss banners on a timer, or leave them until you are ready

## Features

**Position**
- Drag the indicator on the screen preview, or use offset sliders for pixel-perfect placement
- Nine anchor points: corners, edges, center
- Independent position settings per physical display
- Force all banners to a specific screen regardless of where they originate

**Banner style**
- Scale notification banners from 50% to 250%; the slider snaps to 100% to return to the native size
- Tint the banner background with any color: eight quick presets or a full color picker
- Choose an appear animation: Default (system), Slide, Bounce, Fade, or Scale
- When scale is not 100%, a tint is set, or banner mode is forced, NotificationNanny replaces the system banner with its own custom window showing app icon, sender, message, timestamp, a dismiss button, and a Show button on hover
- Per-group banner mode: always native (system), always custom overlay, or let the scale and tint decide

**Per-app rules (Exceptions)**
- Create named groups of apps and give each group its own position, display, banner type, scale, and tint color
- Apps not in any group use the global defaults
- Test each group with a sample notification straight from the settings

**General**
- Auto-dismiss: clear banners automatically after a configurable number of seconds (1 to 300)
- Launch at login via SMAppService
- Pause while screen sharing: suppress all repositioning during screen capture sessions
- Don't move Notification Center: skip repositioning when the NC panel is focused
- Hold while display is asleep: queue banners that arrive during sleep and show them on wake, with dismiss timers restarting fresh

**Organisation**
- Presets: save and switch named configurations covering position, scale, animation, tint, hold-while-asleep, and per-app groups (up to 5)
- Backup and restore: export all settings to JSON and import on another Mac

**Logs**
- In-app log viewer showing the last 500 events from the banner engine, useful for debugging unexpected behavior

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

NotificationNanny uses the macOS Accessibility API to observe the notification center process. When a banner appears it repositions or replaces it according to your rules. For scaled, tinted, or custom banners it intercepts the notification, moves the system banner off-screen, and shows its own window matching the macOS banner style. This relies on private internals, so Apple can change the behavior in any OS update. The app sandbox is disabled because cross-process Accessibility access requires it.

Supports macOS 14 Sonoma, macOS 15 Sequoia, and macOS 26 Tahoe.

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
- Banner scale: resize notifications from 50% to 250%; snaps to 100% (native macOS) with a magnetic slider
- Banner tint: overlay any color on the banner background using quick color presets or a full color picker; clearable at any time
- Appear animation: Default (macOS system slide), Slide, Bounce, Fade, Scale; previewed live in the settings panel
- Custom banner: replaces the system banner with a styled window showing app icon, sender, message, timestamp, dismiss button, and Show button on hover; activates automatically when scale is not 100%, a tint is set, or banner mode is forced
- Per-group banner mode: native (macOS system), custom overlay, or auto (follow scale and tint)
- Per-app exceptions: group apps and give each group its own position, display, banner type, scale, and tint color
- Auto-dismiss: clear banners automatically after a configurable number of seconds (1 to 300)
- Hold while display is asleep: queue banners that arrive during sleep and show them on wake with a fresh dismiss timer
- Pause while screen sharing: suppress repositioning during screen capture sessions
- Don't move Notification Center: skip repositioning when the NC settings panel is focused
- Presets: save and switch named configurations covering position, scale, animation, tint, hold-while-asleep, and per-app groups (up to 5)
- Backup and restore: export all settings to JSON and import on another Mac
- In-app log viewer: last 500 events from the banner engine, filterable and copyable
- Context-aware test notification: fires a sample banner using the currently active rule for any group
- App name memory: known apps saved to disk and survive reinstalls and UserDefaults resets
- Launch at login via SMAppService
- Enable/disable toggle to suspend all customization without changing any settings
- Automatic Accessibility permission reset on binary update so Homebrew upgrades prompt cleanly
- Works on macOS 14 Sonoma, macOS 15 Sequoia, and macOS 26 Tahoe

### Tags

`macos` `menu-bar` `menubar-app` `status-bar` `tray-app` `notifications` `notification-banner` `notification-center` `notification-manager` `notification-position` `notification-placement` `notification-customization` `accessibility` `ax-api` `axuielement` `ax-observer` `swiftui` `swift` `swift-package-manager` `appkit` `combine` `macos-app` `mac-utility` `macos-utility` `productivity` `utility` `customization` `window-management` `multi-monitor` `multiple-displays` `open-source` `no-telemetry` `no-subscription` `lightweight` `native` `homebrew` `homebrew-cask` `macos-14` `macos-15` `macos-26` `sonoma` `sequoia` `tahoe`

</details>
