# NotificationNanny

A lightweight macOS menu-bar app that repositions native notification banners to any corner or edge of your screen — instead of the default top-right.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## Features

- Place notifications in any of 9 positions: top-left, top-center, top-right, middle-left, center, middle-right, bottom-left, bottom-center, or bottom-right.
- Lives entirely in the menu bar — no Dock icon, no clutter.
- Optional launch at login.
- No network access, no telemetry.

---

## Requirements

- macOS 13 Ventura or later
- **Accessibility permission** (prompted on first launch)

---

## Installation

### Pre-built app

Download the latest release from the [Releases](../../releases) page, unzip, and drag `NotificationNanny.app` to your `/Applications` folder.

### Build from source

Xcode Command Line Tools are sufficient — a full Xcode install is not required.

```sh
git clone https://github.com/yourname/NotificationNanny.git
cd NotificationNanny
./build-app.sh --install    # builds and copies to /Applications
```

Other build options:

| Command | Effect |
|---|---|
| `./build-app.sh` | Build only; output at `build/NotificationNanny.app` |
| `./build-app.sh --run` | Build and launch immediately |
| `./build-app.sh --install` | Build and copy to `/Applications` |

For a universal binary (Intel + Apple Silicon), set `UNIVERSAL=1` (requires full Xcode):

```sh
UNIVERSAL=1 ./build-app.sh --install
```

---

## First-time setup

1. Launch **NotificationNanny** — a bell icon (🔔) appears in your menu bar.
2. Click the icon and choose **Grant Accessibility Permission…**
3. In **System Settings → Privacy & Security → Accessibility**, enable NotificationNanny.
4. Click the menu-bar icon again and select a notification position.
5. Send a test notification to confirm:
   ```sh
   osascript -e 'display notification "It worked!" with title "NotificationNanny"'
   ```

---

## How it works (and the caveats)

> ⚠️ **This is a deliberate workaround, not a supported feature.** macOS exposes no public API for moving notification banners. Everything below relies on undocumented behaviour inside `NotificationCenter.app` (`com.apple.notificationcenterui`). Apple can — and occasionally does — break this without notice. Use it knowing that a future macOS update may render it ineffective.

With that said, here's what NotificationNanny actually does:

1. Requests **Accessibility permission** from the user.
2. Uses the Accessibility API (`AXUIElement`) to attach to the `com.apple.notificationcenterui` process.
3. Subscribes to `kAXWindowCreatedNotification` to be notified whenever a new banner window appears.
4. Sets `kAXPositionAttribute` on each window to move it to the user-selected location.

Because cross-process Accessibility access is incompatible with the App Sandbox, the sandbox is disabled. The app is ad-hoc code-signed with a custom entitlements file so macOS can persistently remember the Accessibility permission grant.

**Other known limitations:**

- The notification still animates in from its default position before being moved — you may see a brief jump depending on your macOS version and machine speed.
- Validated on macOS 13 Ventura through 15 Sequoia. Behaviour on newer releases is not guaranteed.
- Because this attaches to a system process, any macOS update that restructures `NotificationCenter.app` internals could silently break repositioning.

---

## Project layout

```
NotificationNanny/
├── Package.swift
├── Resources/
│   ├── Info.plist                   # LSUIElement = true (menu-bar only)
│   └── NotificationNanny.entitlements
└── Sources/NotificationNanny/
    ├── NotificationNannyApp.swift   # @main entry point, MenuBarExtra scene
    ├── MenuBarContent.swift         # Menu-bar dropdown UI
    ├── AppSettings.swift            # User preferences (UserDefaults-backed)
    ├── NotificationPosition.swift   # 9-position grid + coordinate math
    ├── NotificationRepositioner.swift # AX observer — moves notification windows
    ├── NotificationProbe.swift      # Detects the notification UI process
    ├── ScreenPlacement.swift        # Screen geometry helpers
    └── LaunchAtLogin.swift          # SMAppService launch-at-login integration
```

---

## Privacy

NotificationNanny does not collect, transmit, or store any personal data. The Accessibility permission is used solely to reposition notification windows on your local machine.

---

## License

MIT — see [LICENSE](LICENSE).
