# NotificationNanny
Control where notification banners appear, how they look, which apps get which treatment, and when they show up.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-7.7.0-brightgreen) ![Downloads](https://img.shields.io/github/downloads/chessper53/NotificationNanny/total?style=flat&label=downloads&color=brightgreen&logo=apple) ![Stars](https://img.shields.io/github/stars/chessper53/NotificationNanny?style=flat&label=stars&color=yellow)

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

## Issues and feature requests

I have a full-time job, so responses may take a little while, but nothing goes unread. Found a bug or have an idea? [Open an issue here](https://github.com/chessper53/NotificationNanny/issues).

## What it does

macOS gives you one place for notification banners and no way to change it. NotificationNanny takes that control back.

- Put banners wherever you want on any screen, with nine anchor points and independent settings per display
- Scale them from 50% to 250%, tint the background or text, or replace the system banner entirely with a custom styled one
- Give specific apps their own rules: create named groups with their own position, display, banner type, scale, and tint
- Choose how banners animate in: system default, slide, bounce, fade, or scale
- Hold banners until your display wakes up so nothing disappears while you are away
- Auto-dismiss banners on a timer (1 to 300 seconds), or leave them until you are ready
- Save named presets covering position, scale, animation, tint, and per-app groups, and export/import settings as JSON
- Launch at login, pause repositioning while screen sharing, and skip repositioning when Notification Center is focused
- In-app log viewer showing the last 500 events from the banner engine, for debugging unexpected behavior

## Documentation

For contributors: [Contributing](docs/CONTRIBUTING.md) covers setup and conventions, [Architecture](docs/ARCHITECTURE.md) covers internals and module structure, [Debugging](docs/DEBUGGING.md) covers the local build/run/debug loop, and [Releasing](docs/RELEASING.md) covers how to cut a release.

## How it works

NotificationNanny uses the macOS Accessibility API to observe the notification center process. When a banner appears it repositions or replaces it according to your rules. For scaled, tinted, or custom banners it intercepts the notification, moves the system banner off-screen, and shows its own window matching the macOS banner style. This relies on private internals, so Apple can change the behavior in any OS update. The app sandbox is disabled because cross-process Accessibility access requires it.

Supports macOS 14 Sonoma, macOS 15 Sequoia, and macOS 26 Tahoe.

## Privacy

No data is collected, transmitted, or stored outside your device. The Accessibility permission is used solely to observe and control notification windows on your local machine.

## License

Released under the [MIT License](LICENSE).