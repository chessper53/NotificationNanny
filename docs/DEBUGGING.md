# Debugging NotificationNanny

NotificationNanny drives the macOS Accessibility API against the live
NotificationCenter process, so most debugging happens against a **running, signed
build** with Accessibility permission granted. This guide covers the local
build/run loop and the common gotchas.

## The fast loop: `./dev.sh`

```sh
./dev.sh
```

This does everything you need in one shot:

1. **Kills** the running instance (`pkill -x NotificationNanny`).
2. **Builds** debug (`swift build`).
3. Assembles the `.app` bundle and **ad-hoc codesigns** it (required for
   Accessibility TCC to attach to a stable code identity).
4. **Resets** the app's Accessibility permission (`tccutil reset Accessibility com.notificationnanny.app`).
5. **Launches** the fresh build.

Because step 4 wipes the permission, you'll re-grant Accessibility on each run —
this is intentional: it mirrors a fresh install and surfaces permission bugs early.

## Manual equivalents

```sh
# Kill
pkill -x NotificationNanny

# Build + bundle (release-grade, host arch)
./build-app.sh            # build only
./build-app.sh --run      # build, reset TCC, launch
./build-app.sh --install  # build, copy to /Applications

# Clear Accessibility permission for the app
tccutil reset Accessibility com.notificationnanny.app

# Launch a built bundle
open build/NotificationNanny.app
```

## Why code-signing matters here

Accessibility permission (TCC) is keyed to a code signature. An **unsigned** binary
gets a new identity on every build, so macOS keeps re-prompting and the granted
permission "doesn't stick." Both `dev.sh` and `build-app.sh` ad-hoc sign
(`codesign --force --deep --sign -`) with the app's entitlements so the identity is
stable across rebuilds.

If permission still won't stick:

```sh
tccutil reset Accessibility com.notificationnanny.app
# then re-launch and re-grant via System Settings → Privacy & Security → Accessibility
```

## Logs

- **In-app:** the **Diagnostics** tab (settings window) shows the live activity log
  (last 1000 entries from `NannyLogger`), an AX-tree dump, and a back-to-back burst
  test. Start here for "why didn't this banner move?" questions.
- **Console.app / `log`:** the app logs via `os.Logger` under subsystem
  `com.notificationnanny`. Stream it with:

  ```sh
  log stream --predicate 'subsystem == "com.notificationnanny"' --level debug
  ```

  Useful categories: `focus` (Focus/DND detection), and the AX/reposition logs.

## Common issues

| Symptom | Likely cause | Check |
|---|---|---|
| Banners not repositioning | Accessibility not granted, or app not running | Diagnostics tab health checks; re-grant permission |
| Permission keeps re-prompting | Unsigned build / changed identity | Ensure you launched a signed bundle (`dev.sh`/`build-app.sh`), not the bare `swift build` binary |
| Nothing happens during a Focus mode | `pauseDuringFocus` is on and a Focus is active | Toggle it in General; see `FocusModeMonitor` |
| Desktop widgets won't move | `protectDesktopWidgets` (on by default) treats non-banner windows as widgets | Expected; see [ARCHITECTURE.md](ARCHITECTURE.md) §11 v1.6 |
| Custom overlay shows stale text | Back-to-back NC window reuse | See ARCHITECTURE §8 "Overlay content refresh" |
| Banner briefly huge then snaps | NC reports oversized width while coalescing | Expected; width is clamped (`maxBannerWidth`) |

## Running tests

```sh
make test     # handles CLT-only Testing.framework wiring
# or, with full Xcode:
swift test
```

See the [Makefile](../Makefile) for why CLT-only setups need the framework
symlink dance.

## Reproducing notifications

Use the **test banner** buttons in the settings tabs (per-group test in
Exceptions/Banner, burst test in Diagnostics), or fire a real one:

```sh
osascript -e 'display notification "body text" with title "Test"'
```
