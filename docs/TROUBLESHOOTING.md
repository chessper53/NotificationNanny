# Troubleshooting

Common questions and fixes for NotificationNanny. If none of these help,
[open an issue](https://github.com/chessper53/NotificationNanny/issues) — the
**Help → Report a bug** button in the app pre-fills diagnostics and recent logs
for you.

## Banners aren't moving / nothing happens

1. **Grant Accessibility permission.** Click the bell icon → settings → grant
   access. NotificationNanny can't see or move banners without it.
   - System Settings → Privacy & Security → Accessibility → enable **NotificationNanny**.
2. **Confirm it's enabled.** The menu-bar bell has an on/off toggle, and a
   **Pause / Snooze** option — make sure you're not paused.
3. **Check you're not in a Focus mode** if you enabled *Pause during Focus / Do
   Not Disturb* in General.
4. Open the **Diagnostics** tab and read the health checks — they call out the
   most common misconfigurations directly.

## I granted Accessibility but it still doesn't work

macOS sometimes keeps a stale permission entry, especially after an update:

1. System Settings → Privacy & Security → Accessibility.
2. Toggle **NotificationNanny** off, then on again (or remove it with the "–" and
   re-add the app).
3. Quit and relaunch NotificationNanny.

After a Homebrew upgrade the app resets its own permission so macOS prompts
cleanly — just re-grant when asked.

## Permission resets every time / keeps asking

This is expected right after an update (the binary changed, so macOS re-verifies).
If it happens on *every launch* without updating, make sure you're running the
installed app from `/Applications`, not a copy from Downloads or a quarantined
build.

## Banners look wrong: too big, wrong spot, or flash before settling

- A brief oversized flash on rapid same-app notifications is macOS coalescing
  banners; NotificationNanny clamps the width and settles within a frame.
- If a specific app is always misplaced, check whether it's covered by a **per-app
  group (Exceptions)** with its own position/display.

## My desktop widgets moved / I don't want them touched

Turn on **General → Don't move desktop widgets** (on by default). When on,
NotificationNanny leaves widget windows where you placed them and only repositions
real notification banners.

## Multiple displays

- Position is configured **per physical display** — set it on each screen, or use
  **Force all banners to a specific screen** to override.
- If you connect/disconnect/mirror displays, banners re-evaluate automatically.

## Custom (scaled/tinted/animated) banners

The system banner is replaced with a custom window when scale ≠ 100%, a tint is
set, an animation other than Default is chosen, or a group forces custom mode.
If you want the **native** macOS banner back, set scale to 100%, clear the tint,
choose the Default animation, or set the group's banner mode to Native.

## Notifications during sleep disappear

Enable **Hold while display is asleep** in General — banners that arrive while the
display sleeps are queued and shown on wake with a fresh dismiss timer.

## Updating

```sh
brew update && brew upgrade --cask notificationnanny
```

Or download the latest from the
[Releases page](https://github.com/chessper53/NotificationNanny/releases/latest).
If you installed via Homebrew, the settings panel also offers one-click updates.

## Uninstalling

```sh
brew uninstall --cask notificationnanny      # add --zap to also remove settings
```

Manual install: quit the app, drag it from `/Applications` to the Trash. Settings
live in `~/Library/Application Support/NotificationNanny/` and
`~/Library/Preferences/com.notificationnanny.app.plist`.

## Privacy

NotificationNanny collects and transmits nothing. Accessibility permission is used
only to observe and move notification windows on your Mac. It runs non-sandboxed
because cross-process Accessibility access requires it.

## Supported macOS

macOS 14 Sonoma, 15 Sequoia, and 26 Tahoe. The app relies on private system
internals, so an OS update can change behavior — if something breaks right after a
macOS update, please file an issue with your version.
