# Local lab reference

These tools measure native Notification Center behavior and compare it with the
custom renderer. Run them from the repository root. Build the Lab sender apps first:

```sh
scripts/notify-lab/build.sh
```

Allow notifications for Lab Alpha, Lab Bravo, and Lab Charlie. Set them to
Persistent in System Settings when testing piles. The process running a lab needs
Accessibility; screenshots also need Screen Recording. Quit NotificationNanny before
native probes so its repositioner does not alter the measurements. The scenario and
app runners launch their own build and refuse a competing instance.

## Banner comparison

```sh
scripts/banner-lab/run.sh
scripts/banner-lab/run.sh --light
scripts/banner-lab/run.sh --both
```

The runner compiles the app's actual overlay view, captures it and the native banner
on matching backdrops, and scores the differences. It restores system appearance
after switching it. Install Pillow and NumPy for scoring. Quit NotificationNanny or
keep its banner animation at Default while capturing native banners.

Results are under `build/banner-lab`: captures in `cap/<appearance>/` and comparison
sheets named `sheet-<appearance>-ours.png`. Lower errors mean a closer match.

The compiled `build/banner-lab/lab` accepts:

```text
real <backdrop...>                         capture native banners
prod <name> [key=value...] -- <backdrop...> capture the actual app view
cand <name> [key=value...] -- <backdrop...> capture an AppKit candidate
theme light|dark                          set system appearance
real-states <backdrop>                    capture native interaction states
prod-states <backdrop>                    capture matching app states
```

Backdrops: `black white gray red blue stripes checker wallpaper`. The last uses
the current desktop. Production parameters include `title`, `subtitle`, `body`,
`height`, `scale`, and `tint=red`. State captures include collapsed, hovered,
expanded details, an open reply, and a typed reply. Their frames go to `states.txt`.

```sh
python3 scripts/banner-lab/score.py --appearance light --sheet ours
python3 scripts/banner-lab/states_sheet.py light gray
python3 scripts/banner-lab/tune.py light 'LIGHT_WASH=0.05' 'LIGHT_WASH=0.15 RIM=0.2'
```

The scorer reports mean absolute pixel error from 0 to 255 for the full banner,
background glass, text, and icon. `-v` adds backdrop details; `--sheet` writes
`sheet-APPEARANCE-NAME.png` with differences amplified threefold. The state sheet
reads native and production state captures and writes `states-sheet.png`. The
tuner compares `NN_LOOK_` candidates on white, black, and gray, reports interior
and edge errors, and restores system appearance when finished.

## Live banner scenarios

```sh
scripts/notify-lab/scenario.sh --custom --seconds 10 0:Alpha 0.6:Bravo 0.6:Charlie
scripts/notify-lab/matrix.sh
scripts/notify-lab/matrix.sh --app build/NotificationNanny.app scenario-name
```

The scenario runner backs up every preference it touches, restores keys individually
on exit, and verifies restoration. It uses the terminal's Accessibility grant and
isolates logs from Application Support. Its exit status is the number of failed
watcher checks. With no posts it measures idle behavior.

Posts are ordered and use seconds since the previous post:

| Post | Effect |
| --- | --- |
| `delay:App[:title]` | Send from Alpha, Bravo, or Charlie |
| `delay:Script[:title]` | Send a Temporary Script Editor notification through osascript |
| `delay:close:App` | Close that Lab app's banner |
| `delay:panel` | Toggle Notification Center through the clock |
| `delay:clock:N` | Click display N's clock; ordering comes from `watch --screens` |
| `delay:expand:App` | Expand the Lab app's stack in the open panel |
| `delay:focus:on` or `delay:focus:off` | Change the fake Focus store; requires `--focus` |
| `delay:wake` | Simulate a system wake |
| `delay:shot:name` | Save a screenshot under `build/notify-lab` |

| Option | Meaning |
| --- | --- |
| `--position P` | Anchor, default `bottomRight` |
| `--x-offset N`, `--y-offset N` | Placement offsets in points |
| `--auto-dismiss S` | Dismiss delay; zero uses the system default |
| `--custom` | Enable the custom renderer using scale 1.002 |
| `--scale F` | Custom scale, also enables the custom renderer |
| `--newest-at-bottom` | Reverse custom pile ordering |
| `--seconds N` | Watch duration, default 10 |
| `--app PATH` | Build to launch, default `build/NotificationNanny.app` |
| `--oslog` | Capture extra debug output; avoid it for timing measurements |
| `--nc-follow` | Let the native panel follow banners to their screen |
| `--display N` | Force display N from `watch --screens` |
| `--keep-existing` | Preserve banners already present at startup |
| `--group App:P[:mode]` | Repeatable group override, with optional `native` or `custom` mode |
| `--focus` | Enable pausing with an isolated, initially active fake Focus store |

Outputs are `build/notify-lab/last-app.log`, `logs/`, `last-run.txt`, and optionally
`last-oslog.txt`; the runner also prints CPU time and memory. Matrix results and
associated app logs are under `build/notify-lab/matrix/`.

The compiled `build/notify-lab/watch` samples every 50 ms and reports persistent
offscreen, swallowed, hidden, and overlapping banners. It returns the failed check
count. Additional commands are:

```text
watch <seconds> [--quiet]
watch --locked             succeed when the screen is locked
watch --windows <pid>      count all process windows, including hidden ones
watch --screens            print display IDs and stable keys
watch --clock              press the menu bar clock
watch --click-clock N      click a particular display's clock and restore the pointer
watch --expand Alpha       expand only that Lab stack
watch --wake               notify an app running with NN_LAB=1
watch --close-all          close only Lab banners
watch --close-app Bravo    close one Lab app's banners
watch --actions            print Lab banner subroles and localized action names
```

Invoke sender binaries inside `build/notify-lab/Lab App.app/Contents/MacOS/notifier`
with a title and body. `--actions` supplies Archive, Snooze, and Reply; `--reply`
supplies Reply only; `--subtitle Text` adds a subtitle. `--clear` removes that app's
delivered notifications. Launches without arguments receive action responses,
append them to `responses.log` beside the Lab apps, and post nothing new.

## Custom panel runner

```sh
scripts/panel-lab/app.sh post:Alpha:Example open wait:1 state shut
scripts/panel-lab/compare.sh
```

The app runner lists only Lab notifications by default, restores and checks its
preferences, and clears Lab notifications afterward. The comparison captures only
Lab rows over a gray backdrop, in both appearances, collapsed and expanded. It
writes `build/panel-lab/compare-<appearance>.png` and `compare.png`.

Pass steps to `app.sh` in order:

```text
post:App:Title             send from a Lab app
postreply:App:Title        send with Reply only
postlong:App:Title         send a multiline body with actions
postact:App:Title          send with Reply, Archive, and Snooze
open | clock              toggle the clock
clock2                    click the second display's clock
shut                      close only if open
scroll[:gap]              scroll over the panel or between rows
state | frames | count    inspect content, text geometry, or numbers only
shot:name | sshot:name     capture the window or its on screen appearance
click:Text | close:Title   activate a row or click its close button
button:Label              click a button or menu item
rclick:Text | hover:Text   open a row menu or hover its text
type:Text                 type only after confirming native reply focus
responses:N               read the last N Lab action responses
widget | wrclick          click a widget or open its menu
apps:Name                 check whether a process is running
bhover | bbutton | bstate  target banner overlays instead of panel rows
brclick:Text              open a custom banner menu
menu[:Item]               inspect the open menu and optionally select an item
clicktop | pframe         click the first row immediately or report the panel frame
pref:key | settings       read a preference or open the panel's Settings tab
sdrag:dx,dy               drag the Settings preview; default 0,40
film:seconds | filmend    record over gray, report settling, then delete the recording
wait:seconds              pause before the next step
```

`PANEL_APPEARANCE=light` changes the app's appearance without changing the system.
`NN_SET="key=YES key2=0.9 key3=left"` supplies more preferences to restore on exit.
`KEEP_LAB=1` retains Lab notifications for another run. `NN_ATTACH=pid` drives an
existing process with its own Screen Recording grant; that process's caller owns
preference setup and restoration. An empty `PANEL_FILTER=` includes personal
notifications, so use `count` rather than content dumps or screenshots in that mode.

## Native panel experiments

```sh
scripts/panel-lab/run.sh
scripts/panel-lab/run.sh uuid actions list
scripts/panel-probe.sh --rows 12
swift scripts/ax-probe.swift
scripts/panel-lab/nc-stall.sh 3 0.3
```

The panel runner seeds Lab rows and clears them on exit. Default experiments are
`uuid`, `flash-native`, `flash-react`, `flash-prepark`, `tap`, `skin`, and `actions`.
Other runner selections include `prepark-only`, `list`, and `ids`. Flash recordings
cover the opening strip, yield numerical measurements, and are deleted.

The compiled `build/panel-lab/lab` also accepts direct experiments:

| Command | Measurement |
| --- | --- |
| `uuid`, `ids`, `host` | Notification identity and host lifetime |
| `flash native`, `flash react`, `flash prepark` | Native exposure with different parking times |
| `tap`, `skin`, `hover-test` | Click routing, passthrough, and inactive hover delivery |
| `actions`, `act`, `type`, `panel-reply` | Lab action and reply delivery |
| `tree [keep]`, `real-times` | AX structure or native times; redact personal text |
| `real-hover Title [menu]`, `parked-menu [Item]` | Native Lab row hover and menu behavior |
| `widget-park <out> <x\|top\|off\|home>` | Widget rendering with an edge, row, no pixels, or the whole host visible |
| `widget-cover`, `widget-menu` | Widget captures and menus |
| `panel-shots`, `frames`, `unpark` | Lab row captures, text geometry, or host restoration |

Some experiments accept extra arguments; inspect their command branches in
`scripts/panel-lab/lab.swift` for exact values. The `ui-` commands drive a specified
NotificationNanny PID and are normally invoked by `app.sh`. `NN_LAB_TARGET=banners`
selects overlays instead of the panel; `NN_LAB_WHEEL` changes the scroll step.

Widget parking writes `<out>.wid` for the screenshot helper, then retains only
widget crops and removes the full capture. `widget-menu` dismisses native menus
without selecting an action. Widget text is redacted unless `--text` is explicitly
requested. Reply experiments send real keys only after confirming the Lab field has
keyboard focus. `nc-stall.sh` pauses Notification Center for the given duration
after a banner and installs cleanup to resume it.

The standalone panel probe writes `build/panel-probe/report.txt` and `tree.txt`.
It checks detection, tree shape, list completeness, AX events, arrivals, parking,
compositor alpha, and expansion toggles. It closes the panel, restores its host,
and clears Lab notifications. The AX probe checks whether host positions remain
writable and counts window and layout events across banner arrivals.

## Screenshots and recording analysis

```sh
scripts/panel-lab/shot.sh screencapture -x /tmp/lab.png
scripts/panel-lab/shot.sh window WINDOW_ID /tmp/widget.png
python3 scripts/panel-lab/flash.py recording.mov
python3 scripts/panel-lab/settle.py recording.mov
```

The screenshot helper builds `build/panel-lab/Shot.app` once and reuses it to retain
its Screen Recording grant. Delete that generated app only when rebuilding is
necessary, then grant access again. Results go to an output sidecar or
`build/panel-lab/shot.txt` because the launcher cannot convey its exit status.

Flash analysis compares frames with the initial background; settle analysis compares
them with the final frame, exposing a second panel appearance during exit. Both
print measurements and retain no frames. They need ffmpeg and NumPy.

To regenerate the website social image:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
  --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 \
  --screenshot="$PWD/site/assets/social-card.png" "file://$PWD/scripts/social-card.html"
```

Chrome may remain running after writing the image; stop that process afterward.
