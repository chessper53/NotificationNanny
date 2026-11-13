# Live macOS smoke tests

Run this small suite before a release when changing the AX pipeline, banner
placement, custom overlays, or forwarded actions. It exercises the bundled app
from outside its process; the probe never imports NotificationNannyCore.

## Build

From the testing worktree:

```sh
bash scripts/e2e/build.sh
```

This builds the app, the existing Lab Alpha/Bravo/Charlie notification senders,
and a Swift Accessibility probe. It does not install or launch NotificationNanny,
reset permissions, or change the active branch. Build artifacts stay in this
worktree's `build/` and `.build/` directories. Existing `SIGN_IDENTITY`,
`SIGN_KEYCHAIN`, and `DEV_SIGNING=1` options work through the bundle script.

The build uses the selected toolchain. With the current Command Line Tools, it
uses the 26.5 SDK if available, matching the existing lab scripts. Full Xcode is
also supported. `--helpers-only` skips building the main app.

## Prepare the desktop once

Use a dedicated macOS test account for repeatable runs:

1. Grant Accessibility to the terminal or runner launching the suite. The tests
   never prompt for or change this permission.
2. Allow notifications from each Lab app. A first post requests permission:

   ```sh
   "build/notify-lab/Lab Alpha.app/Contents/MacOS/notifier" "Setup" "Allow Lab Alpha"
   "build/notify-lab/Lab Bravo.app/Contents/MacOS/notifier" "Setup" "Allow Lab Bravo"
   "build/notify-lab/Lab Charlie.app/Contents/MacOS/notifier" "Setup" "Allow Lab Charlie"
   ```

3. In System Settings > Notifications, enable **Persistent** alerts for all three
   Lab apps. This is required so the system's temporary-banner timeout cannot
   masquerade as NotificationNanny's auto-dismiss timer.
4. Keep the desktop unlocked, disable actual macOS Focus/Do Not Disturb, and
   leave Notification Center closed. Quit any running NotificationNanny yourself.
   The runner refuses to stop an existing instance.

Accessibility is sufficient for the probes; these tests do not capture screen
pixels and do not require Screen Recording. Permission attribution can depend
on how the runner was launched, so use the same terminal/runner for setup and
execution.

## Run

```sh
python3 scripts/e2e/run.py --check
python3 scripts/e2e/run.py
# Or one scenario:
python3 scripts/e2e/run.py --only custom-action
```

`--check` reads desktop and sender authorization state without posting a
notification or launching NotificationNanny. Missing prerequisites exit **69**;
an executed test failure exits **1**; a passing suite exits **0**. A prerequisite
lost during an executing test is recorded as a failure. Interrupts exit **130**
and attempt the same cleanup.

The default app is `build/NotificationNanny.app`; `--app /path/to/app` selects
another build from this testing branch. The runner rejects binaries predating
the isolated E2E launch configuration and checks its startup acknowledgement.

## Coverage

| Scenario | Required evidence |
| --- | --- |
| `native-position` | A uniquely titled Lab notification appears natively and settles at bottom-left within 12 points; no custom replacement exists. |
| `custom-stack-dismiss` | Three uniquely titled notifications have visible custom overlays on one screen, with no overlap; they remain until near the configured 5-second timer, then both overlays and backing banners disappear within the bounded deadline. |
| `custom-action` | Archive is pressed on the uniquely titled custom banner; Lab Alpha records that exact title and action in its own response log. |

Every awaited state must remain stable briefly. Missing deliveries, permission
failures, app exits, wrong placement, duplicated/missing pile members, stale
response logs, and missed cleanup fail rather than passing on an empty desktop.
Per-scenario app logs, timestamped JSON observations, and a suite `results.json`
are retained in `build/e2e/runs/`.

Each scenario seeds a fresh `com.notificationnanny.e2e.<UUID>` preferences suite
and a run-local known-apps file. It skips automatic login registration, the app's
own notification permission request, and the release-only Accessibility reset. Cleanup stops only the spawned
process, clears only the Lab apps' notifications, and deletes the test preference
suite. It does not replace or restore production preferences. A shared lock
prevents concurrent E2E suites across worktrees, but other desktop automation
must also be kept idle during a run.

These tests configure the app through the isolated store. They do not cover
clicking Settings controls, reply text entry, widgets, actual display sleep,
multi-display routing, or every supported macOS version. Existing panel/banner
labs remain exploratory tools. No dedicated CI machine or Xcode UI test project
is introduced.

## Fast checks without desktop automation

```sh
python3 -m unittest discover -s scripts/e2e -p 'test_*.py' -v
bash scripts/test.sh --filter E2ESettingsTests
```

The Python checks protect against false-positive verdicts, and the Swift tests
check settings/data isolation. They do not substitute for a live smoke run.

The existing in-process AX integration test now requires an explicit opt-in:

```sh
NN_RUN_AX_TESTS=1 bash scripts/test.sh --filter AXIntegrationTests
```

It fails if prerequisites are missing and checks a uniquely titled banner's
actual position. Ordinary unit runs leave it disabled, even from a trusted
terminal. With Command Line Tools, the test script may additionally need the
SDK and Testing macro-plugin flags described in `scripts/capture-screenshots.sh`.
