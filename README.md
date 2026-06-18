# NotificationNanny
Control where notification banners appear, how they look, which apps get which treatment, and when they show up.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-7.5.0-brightgreen) ![Downloads](https://img.shields.io/github/downloads/chessper53/NotificationNanny/total?style=flat&label=downloads&color=brightgreen&logo=apple) ![Stars](https://img.shields.io/github/stars/chessper53/NotificationNanny?style=flat&label=stars&color=yellow)

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

## Installation

```sh
brew tap chessper53/notificationnanny https://github.com/chessper53/NotificationNanny
brew install --cask notificationnanny
```

Or download the latest zip from the [Releases page](https://github.com/chessper53/NotificationNanny/releases/latest) and drag `NotificationNanny.app` to your Applications folder.

After installing, click the bell icon in your menu bar and grant Accessibility permission to get started. If you installed via Homebrew, updates are one click from the settings panel.

## What it does

macOS gives you one place for notification banners and no way to change it. NotificationNanny takes that control back.

- Put banners wherever you want on any screen
- Scale them up or down, tint them a color, or replace the system banner entirely with a custom styled one
- Give specific apps their own rules: different position, different display, different banner style
- Choose how banners animate in: system default, slide, bounce, fade, or scale
- Hold banners until your display wakes up so nothing disappears while you are away
- Auto-dismiss banners on a timer, or leave them until you are ready

<details>
<summary>Full feature list</summary>

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

</details>

## How it works

NotificationNanny uses the macOS Accessibility API to observe the notification center process. When a banner appears it repositions or replaces it according to your rules. For scaled, tinted, or custom banners it intercepts the notification, moves the system banner off-screen, and shows its own window matching the macOS banner style. This relies on private internals, so Apple can change the behavior in any OS update. The app sandbox is disabled because cross-process Accessibility access requires it.

Supports macOS 14 Sonoma, macOS 15 Sequoia, and macOS 26 Tahoe.

## Privacy

No data is collected, transmitted, or stored outside your device. The Accessibility permission is used solely to observe and control notification windows on your local machine.

## Documentation

- [CHANGELOG.md](CHANGELOG.md) — release history and per-version changes
- [ARCHITECTURE.md](ARCHITECTURE.md) — internals, design patterns, and module structure

## Issues and feature requests

Open an issue. I read them all and work through them when I can. I have a full-time job so responses may take a little while, but nothing goes unread. [Open an issue here](https://github.com/chessper53/NotificationNanny/issues).

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=chessper53/NotificationNanny&type=Date)](https://star-history.com/#chessper53/NotificationNanny&Date)

---

<details>
<summary>Tags</summary>

`macos` `menu-bar` `menubar-app` `status-bar` `tray-app` `notifications` `notification-banner` `notification-center` `notification-manager` `notification-position` `notification-placement` `notification-customization` `accessibility` `ax-api` `axuielement` `ax-observer` `swiftui` `swift` `swift-package-manager` `appkit` `combine` `macos-app` `mac-utility` `macos-utility` `productivity` `utility` `customization` `window-management` `multi-monitor` `multiple-displays` `open-source` `no-telemetry` `no-subscription` `lightweight` `native` `homebrew` `homebrew-cask` `macos-14` `macos-15` `macos-26` `sonoma` `sequoia` `tahoe`

</details>
