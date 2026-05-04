# NotificationNanny

A tiny macOS menu-bar app that repositions native notification banners to wherever
you want them on screen (top-left, top-center, bottom-right, etc.) instead of the
default top-right corner.

## Status

First draft / scaffold. The plumbing is in place and the menu-bar UI works, but
this needs to be wrapped in an Xcode App target before it can run as a real
menu-bar app, and the repositioning behaviour should be smoke-tested on your
macOS version.

## How it works (and the caveats)

macOS does **not** expose a public API for moving notification windows. Banners
are drawn by `NotificationCenter.app` (`com.apple.notificationcenterui`) and
their position is hard-coded.

The standard workaround — what NotificationNanny does — is:

1. Ask the user for **Accessibility** permission.
2. Use the Accessibility API (`AXUIElement`) to attach to the
   `com.apple.notificationcenterui` process.
3. Subscribe to `kAXWindowCreatedNotification` so we get told whenever a new
   notification window appears.
4. Set `kAXPositionAttribute` on each window to the user-selected location.

Limitations / things to know:

- This relies on undocumented behaviour and Apple can break it in any macOS
  release. Tested mental model is macOS 13–15; YMMV on newer versions.
- App Sandbox must be **off** (cross-process AX is sandbox-incompatible).
- The notification still animates in from its default location and is then
  moved — depending on macOS version you may see a brief jump. A future
  iteration could try to hide-then-show, but that's beyond the first draft.

## Project layout

```
NotificationNanny/
├── Package.swift                          # for SwiftPM / Xcode SPM tooling
├── README.md
├── Resources/
│   ├── Info.plist                         # LSUIElement = true (menu bar only)
│   └── NotificationNanny.entitlements     # sandbox off
└── Sources/NotificationNanny/
    ├── NotificationNannyApp.swift         # @main, MenuBarExtra scene
    ├── MenuBarContent.swift               # the dropdown menu
    ├── AppSettings.swift                  # @Published settings persisted in UserDefaults
    ├── NotificationPosition.swift         # 9-position grid + AX coord math
    └── NotificationRepositioner.swift     # AX observer that moves the windows
```

## Build & run (no Xcode required)

```sh
./build-app.sh --run        # builds + launches
./build-app.sh --install    # builds + copies to /Applications
./build-app.sh              # builds only, output in build/NotificationNanny.app
```

The script:
1. Compiles via `swift build -c release` (Command Line Tools is enough).
2. Assembles a `NotificationNanny.app` bundle with the right `Info.plist`
   (`LSUIElement = true`, so no Dock icon).
3. Ad-hoc codesigns it with the entitlements file — required so macOS can
   remember the Accessibility permission.

For a universal (Intel + Apple Silicon) build, set `UNIVERSAL=1` (requires full
Xcode).

### Or build it in Xcode

1. **File → New → Project → macOS → App**, name `NotificationNanny`, SwiftUI.
2. Replace the auto-generated `*.swift` with the files in `Sources/NotificationNanny/`.
3. In **Info**: add `Application is agent (UIElement)` = `YES`.
4. In **Signing & Capabilities**: remove App Sandbox.
5. Deployment target: **macOS 13+** (for `MenuBarExtra`).

## First launch

1. Click the bell icon in the menu bar.
2. Click **Grant Accessibility Permission…** — System Settings will open.
3. Enable NotificationNanny under **Privacy & Security → Accessibility**.
4. Pick a position from the menu.
5. Send yourself a test notification (`osascript -e 'display notification "hi" with title "test"'`).

## Ideas for v0.2

- Per-screen position (multi-monitor)
- Custom pixel offset / drag-to-position UI
- Stack direction (down / up) when multiple banners are visible
- LaunchAtLogin (via `ServiceManagement`'s `SMAppService`)
- Detect notification-vs-other-window more robustly (subrole / role checks)
