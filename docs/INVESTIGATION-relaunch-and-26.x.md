# Investigation: "no menu bar icon on relaunch" + "banners stay top-right on 26.6.2"

Working notes for the GitHub issue where one reporter says the app does not come
back on a second launch, and a second reporter says macOS 26.6.2 broke
repositioning outright and claims the notification AX hierarchy is now
unworkable.

The two reports are **not one bug**. They are at least two independent causes
that happen to produce the same user-visible symptom ("no icon, notifications in
the corner"), which is why the thread reads as a single catastrophic regression.

## Ground truth measured on macOS 27.0 (26A428)

Run of [`scripts/ax-probe.swift`](../scripts/ax-probe.swift) against a live
banner. This is measurement, not inference:

```
macOS 27.0.0
=== window tree (2 window(s)) ===
AXWindow/AXSystemDialog pos=(0,0) size=1710x1107 posSettable=true
  AXGroup/AXHostingView pos=(0,0) size=1710x1107 posSettable=false
    AXGroup pos=(958,0) size=752x1087 posSettable=false
      AXScrollArea ...

=== can the host window be moved, and does it stay moved? ===
host 1710x1107: posSettable=true setError=0
  requested  (-250,100)
  read back  (-250,100)   applied=true
  after 1.2s (-250,100)   held=true
  >> OK: repositioning works on this system.

=== which events does a banner actually emit? ===
  AXWindowCreated: 0
  AXFocusedWindowChanged: 0
  AXWindowMoved: 0
  AXMainWindowChanged: 0
  AXUIElementDestroyed: 3
  AXLayoutChanged: 3
```

Two conclusions follow directly.

**The "Apple broke it, needs a core rework" claim is wrong.** The fullscreen
`AXSystemDialog` host is still position-settable, the write lands, and it holds
after settling. What is read-only is the *banner view* inside the host — which
has been true since the SwiftUI move and is exactly why this app moves the host
rather than the banner. A reporter who tried to set the banner element's own
position would see "you can set position all day, the layout engine ignores it"
and conclude the API is dead. That is the wrong element, not a broken API.

**`AXWindowCreated` never fires for a banner.** The host window persists between
banners, so a new banner is a layout change inside an existing window, never a
new window. The only arrival signal is `AXLayoutChanged`.

## Why it works on the dev machine and not for users

`feat/8.0-ui-and-performance` subscribes to five notifications
([AXObserverController.swift:17-21](../Sources/NotificationNannyCore/Engine/AXObserverController.swift#L17-L21)):
window-created, focused-window-changed, window-moved, main-window-changed,
element-destroyed. **`kAXLayoutChangedNotification` is not among them.**

The fix already exists on `migrate-app-to-26.6.2` (commit `dddfaf6`) and is *not*
merged into `feat/8.0-ui-and-performance`. The local dev build that "works fine on
Golden Gate" is that branch. So the comparison that made this look like a
reporter-side problem was never like-for-like.

This also explains the intermittency rather than a clean total failure.
`handleAXEvent` calls `scheduleDestroySweep()` on *every* element-destroyed event
([NotificationRepositioner.swift:152](../Sources/NotificationNannyCore/Engine/NotificationRepositioner.swift#L152)),
and that sweep repositions whatever is currently on screen. Destroys do still
fire (3 of them above). So a banner sometimes gets moved as a side effect of a
*previous* banner's teardown, and sometimes does not. That is the same class of
artifact as the flicker the reporter describes in `notif-mover`: reacting to the
wrong signal and correcting late.

## Ranked list of things to check

### 1. Missing `AXLayoutChanged` subscription — confirmed, now fixed on this branch

Measured above. `dddfaf6` has been ported onto `feat/8.0-ui-and-performance`. It
was not a clean cherry-pick: the notification list had moved out to
`AXObserverController`, while the `layoutChangeDebouncer` and sweep handling stay
in `NotificationRepositioner`.

**Still unverified on a real machine.** The honest test is the *first* banner
after a cold start, with no prior banner to have triggered a destroy sweep —
that is the one case the old accidental path cannot cover. A banner that moves
only after you have already had one banner proves nothing.

### 2. "Hide menu bar icon" is a one-way door — strong candidate for report #1

[SettingsView+GeneralTab.swift:41](../Sources/NotificationNannyCore/UI/SettingsView/SettingsView+GeneralTab.swift#L41)
is a bare toggle under "Startup", no warning, no stated way back. The reporter
said "I set preferences and all worked fine. Now, I don't see the icon."

Check: does the recovery path actually work? `applicationShouldHandleReopen`
opens Settings when the icon is hidden
([NotificationNannyApp.swift:278-281](../Sources/NotificationNanny/NotificationNannyApp.swift#L278-L281)),
but that only fires if LaunchServices routes the re-open to the existing process.
If a second process spawns instead, `terminateIfAlreadyRunning` calls
`existing.activate()` and exits — and `activate()` on an `LSUIElement` app with no
windows shows nothing at all. Worth reproducing both routes. If the second route
is reachable, hiding the icon is genuinely unrecoverable without Activity Monitor.

Regardless of outcome: the toggle needs a confirmation that tells the user how to
get back, or should re-show the icon on re-launch.

### 3. `resetTCCIfBinaryChanged` wipes permission on every upgrade

[NotificationNannyApp.swift:250-267](../Sources/NotificationNanny/NotificationNannyApp.swift#L250-L267)
runs `tccutil reset Accessibility` whenever the executable's mtime differs from
the stored one, in release builds only (`#if !DEBUG`). A `brew upgrade --cask`
replaces the binary, so every upgrade silently revokes the user's Accessibility
grant. The app then runs with a slashed bell and does nothing, which looks
exactly like "it stopped working after I reinstalled."

Note the `#if !DEBUG`: this code path has never once run on the dev machine.

Things to establish:
- Does `tccutil reset` on a live, AX-trusted process terminate it? If yes, this
  alone reproduces "the app vanishes."
- Is the reset still needed at all? It exists because ad-hoc signing changes the
  cdhash per build, so a stale TCC row can shadow the new binary. That is a
  *development* problem, and `dev.sh` already resets explicitly. Shipping it to
  users may be pure downside.

I checked and ruled out one variant of this: a `Date` precision theory where the
mtime fails to round-trip through `UserDefaults` and fires the reset on *every*
launch. Measured — it round-trips exactly, including sub-second APFS timestamps.
The reset only fires on genuine binary change.

### 4. App lifecycle is wired through `@StateObject`, not the delegate adaptor

`NotificationNannyApp` has only a `Settings { EmptyView() }` scene and builds the
coordinator as `@StateObject`
([NotificationNannyApp.swift:8-14](../Sources/NotificationNanny/NotificationNannyApp.swift#L8-L14)),
setting `NSApp.delegate = self` from inside `init()`. That means every launch
side effect — status item, permission observation, login item — depends on
SwiftUI choosing to evaluate `body` for a scene that renders nothing, and the
delegate is installed too late to ever receive `applicationDidFinishLaunching`.

This is a known-fragile pattern and the only candidate that would plausibly
produce "launches once, then nothing at all" with no crash. Check first whether
it actually misfires; `@NSApplicationDelegateAdaptor` is the correct shape either
way.

### 5. Ad-hoc signing and Gatekeeper

The app is ad-hoc signed (`codesign --sign -` in
[build-app.sh:75](../scripts/build-app.sh#L75)) and the cask strips quarantine in a
postflight. Worth checking, though it ranks below the above:

- Users who download the ZIP from Releases directly, rather than via brew, keep
  the quarantine bit. An unsigned/ad-hoc quarantined app can be run under App
  Translocation from a randomized read-only path, which would break the
  path-keyed TCC grant on every launch and also defeat the
  `bundlePath.hasPrefix("/Applications/")` check in `autoEnableLoginItemIfNeeded`.
- Test the actual shipped artifact, not a local build: download the release ZIP,
  unzip via Finder, launch twice, and check `AXIsProcessTrusted()` each time.

Notarization would settle this class of problem but costs $99/yr; not worth it
before establishing that translocation is actually what reporters hit. Ask the
reporters *how* they installed — brew cask or ZIP — since only the ZIP path is
exposed.

## What to ask the reporters

Both reports are missing the diagnostics bundle the template asks for. Narrow
questions that separate the causes above:

- Is "Hide menu bar icon" turned on in Settings > General > Startup?
- Installed via `brew install --cask`, or by downloading the ZIP from Releases?
- Was this a fresh install or an upgrade over an existing version?
- With the app supposedly not running: does `pgrep -x NotificationNanny` print a
  pid? (Report #2 says the process *is* there, report #1 says it is not — that
  difference alone means these are different failures.)
