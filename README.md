# NotificationNanny

A macOS menu-bar app that lets you reposition notification banners to any location on any of your displays, instead of being stuck in the top-right corner.

I work full time, but I'm happy to look at any issues that come up. Feel free to open one!

<img width="366" height="805" alt="image" src="https://github.com/user-attachments/assets/8e315785-589c-4a41-9714-325dc6d42dd9" />




![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## What's New in v6.1

### Per-app positioning rules

Notifications from different apps can now go to different positions. Create named groups, assign apps to them, and each group gets its own drag-to-position tile and fine-tune sliders.

**Example setup:**
- *Priority Messages* → Microsoft Teams + WhatsApp → bottom-left
- *Calendar* → Calendar + Reminders → top-center  
- Everything else → top-right (Default)

Apps are detected automatically as notifications arrive and remembered permanently, so you only need to assign them once. The **Test** button is context-aware: while editing a group it fires a test notification using that group's exact placement so you can see exactly where it lands.

### Other improvements in v6.1
- App names persist across reinstalls in `~/Library/Application Support/NotificationNanny/known_apps.json`
- Notification positioning now re-evaluates on each animation hold, fixing a race where the group placement could be ignored if the banner wasn't fully rendered at the moment it appeared

---

## Installation

```sh
brew tap chessper53/notificationnanny https://github.com/chessper53/NotificationNanny
brew install --cask notificationnanny
```

To upgrade to the latest version:

```sh
brew upgrade --cask notificationnanny
```

> **Coming from an older install?** If you get a remote mismatch or `already installed` error, uninstall and retap:
> ```sh
> brew uninstall --cask notificationnanny
> brew untap chessper53/notificationnanny
> brew tap chessper53/notificationnanny https://github.com/chessper53/NotificationNanny
> brew install --cask notificationnanny
> ```

A bell icon appears in your menu bar. On first launch, click **Grant Accessibility Permission…** and enable NotificationNanny under **System Settings → Privacy & Security → Accessibility**.

---

## Usage

Click the menu bar bell to open the panel. Drag the purple chip around the screen tile to set your preferred position, or use the horizontal and vertical sliders for pixel-perfect placement. Hit **Send Test Notification** to fire a banner and see exactly where it lands. Settings are remembered per display, so you can have different positions on different screens.

**Screen selector** (multi-display only): Force all banners onto a specific display, or leave it on Auto to follow macOS.

**App Rules**: Create named groups and assign specific apps to each — every group gets its own drag-to-position tile and fine-tune sliders. For example, create a "Work" group for Microsoft Teams and position it bottom-left, and a "Social" group for WhatsApp and Messages at top-center. Apps not assigned to any group use the Default position. NotificationNanny learns which apps have sent notifications automatically, so they appear in the "Add app" menu as soon as you receive one.

**Auto-dismiss**: Enable this to have banners slide off-screen automatically after a chosen number of seconds.

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

---

<details>
<summary>Full feature list &amp; tags</summary>

### Features

- **Per-app rules**: assign apps to named groups, each with its own position — e.g. Teams bottom-left, Calendar top-center, everything else top-right
- Drag-to-position tile: place notification banners anywhere on screen with a miniature display preview
- Pixel-perfect fine-tuning with horizontal and vertical offset sliders
- Multi-display support: independent position settings per physical screen, with a screen-force override
- Auto-dismiss: automatically slide banners off-screen after a configurable number of seconds
- Context-aware test notification: fires a sample banner using the currently selected rule's placement
- App name memory: known apps saved to disk and survive reinstalls
- Launch at login support via SMAppService
- Enable/disable toggle to suspend all repositioning without changing any settings
- Automatic Accessibility permission reset on binary update so Homebrew upgrades prompt cleanly
- Works on macOS 13 Ventura and later, including macOS 26 Tahoe

### Tags

`macos` `menu-bar` `notifications` `notification-banner` `accessibility` `swiftui` `swift` `macos-app` `productivity` `menubar-app` `notification-manager` `ax-api` `notificationcenter` `swift-package-manager` `no-xcode`

</details>
