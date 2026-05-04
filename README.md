# NotificationNanny
A lightweight macOS menu-bar app that lets you reposition it to any location on your Desktop(s) instead of the default top-right.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## Requirements

- macOS 13 Ventura or later
- **Accessibility permission** (prompted on first launch)

---

## Installation and usage
Later Homebrew support is planned

---

## How it works (and the caveats)

> **This is a deliberate workaround, not a supported feature.** macOS exposes no public API for moving notification banners. Everything below relies on undocumented behaviour inside `NotificationCenter.app` (`com.apple.notificationcenterui`). Apple can — and occasionally does — break this without notice. Use it knowing that a future macOS update may render it ineffective.

With that said, here's what NotificationNanny actually does:

1. Requests **Accessibility permission** from the user.
2. Uses the Accessibility API (`AXUIElement`) to attach to the `com.apple.notificationcenterui` process.
3. Subscribes to `kAXWindowCreatedNotification` to be notified whenever a new banner window appears.
4. Sets `kAXPositionAttribute` on each window to move it to the user-selected location.

Because cross-process Accessibility access is incompatible with the App Sandbox, the sandbox is disabled. The app is ad-hoc code-signed with a custom entitlements file so macOS can persistently remember the Accessibility permission grant.

**Other known limitations:**

- The notification still animates in from its default position before being moved — you may see a brief jump depending on your macOS version and machine speed.
- Validated on macOS Tahoe 26.4.1. Behaviour on newer releases is not guaranteed but should be possible. (If not just open an issue with the macOS version and any relevant details.)
- Because this attaches to a system process, any macOS update that restructures `NotificationCenter.app` internals could silently break repositioning.

---

## Privacy

NotificationNanny does not collect, transmit, or store any personal data. The Accessibility permission is used solely to reposition notification windows on your local machine.

---

## License

MIT — see [LICENSE](LICENSE).
