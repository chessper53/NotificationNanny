# NotificationNanny

A macOS menu-bar app that lets you reposition notification banners to any location on any of your displays, instead of being stuck in the top-right corner.

I work full time, but I'm happy to look at any issues that come up. Feel free to open one!

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## Installation

```sh
brew tap chessper53/notificationnanny https://github.com/chessper53/NotificationNanny
brew install --cask notificationnanny
```

A bell icon appears in your menu bar. On first launch, click **Grant Accessibility Permission…** and enable NotificationNanny under **System Settings → Privacy & Security → Accessibility**.

---

## Usage

Click the menu bar bell to open the panel. Drag the purple chip around the screen tile to set your preferred position, or use the horizontal and vertical sliders for pixel-perfect placement. Hit **Send Test Notification** to fire a banner and see exactly where it lands. Settings are remembered per display, so you can have different positions on different screens.

---

## How it works

> **This is a deliberate workaround, not a supported feature.** macOS exposes no public API for moving notification banners. Everything below relies on undocumented behaviour inside `com.apple.notificationcenterui`. Apple can break this without notice.

NotificationNanny requests Accessibility permission, then uses `AXUIElement` to attach to the `com.apple.notificationcenterui` process. It subscribes to `kAXWindowCreatedNotification` to detect new banners and sets `kAXPositionAttribute` on each window to move it to the chosen location.

Because cross-process Accessibility access is incompatible with the App Sandbox, the sandbox is disabled. The app is ad-hoc signed with a custom entitlements file so macOS can persistently remember the permission grant.

The banner briefly appears at its default position before jumping (an unavoidable race with the system animation). The app has been validated on macOS Tahoe 26; any macOS update that restructures `NotificationCenter.app` internals could silently break repositioning.

---

## Building from source

No Xcode required, just the Command Line Tools:

```sh
git clone https://github.com/chessper53/NotificationNanny.git
cd NotificationNanny
./build-app.sh --run
```

---

## Privacy

NotificationNanny does not collect, transmit, or store any personal data. The Accessibility permission is used solely to reposition notification windows on your local machine.