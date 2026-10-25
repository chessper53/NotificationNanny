#!/usr/bin/env bash
# Runs a debug build of NotificationNanny with the custom Notification Center on, and
# drives it step by step.
#
#   scripts/panel-lab/app.sh step...
#
# Steps, run in order:
#   post:App:Title        a Lab notification (App is Alpha, Bravo or Charlie)
#   open | clock          press the menu bar clock (opens or closes the panel)
#   clock2                a real click on the second screen's clock
#   shut                  close the panel if it is open (a clock press would reopen it)
#   scroll                scroll the wheel over our panel
#   state                 what our panel and Notification Center's show
#   count                 the same as numbers only, for PANEL_FILTER= runs
#   shot:name             capture our panel into build/panel-lab/name.png
#   click:Text            click the text in our panel (a row's title, say)
#   close:Title           click the ✕ of the row with that title
#   button:Label          click a button in our panel ("Show less", "Clear All")
#   widget                click the middle of the first widget picture in our panel
#   apps:Name             whether a process of that name is running
#   wait:seconds
#
# PANEL_FILTER= (empty) lists every app, the user's own too; use count, not state or shot.
# PANEL_APPEARANCE=light draws our panel in Light Mode without touching the system's.
#
# Only the Lab apps are listed in the panel during a run (NN_LAB_PANEL_FILTER), so
# captures never show your own notifications. The only setting written is
# customNotificationCenter; it is put back and checked on exit, along with
# lastBinaryMtime, which the app stamps itself. Lab notifications are cleared.
set -euo pipefail
cd "$(dirname "$0")/../.."

DOMAIN=com.notificationnanny.app
OUT=build/panel-lab
NOTIFY=build/notify-lab
APP=build/NotificationNanny.app
NN_MATCH="\.app/Contents/MacOS/NotificationNanny"
mkdir -p "$OUT"

if pgrep -f "$NN_MATCH" >/dev/null; then
    echo "NotificationNanny is already running; quit it first." >&2
    exit 65
fi

SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d "$SDK" ]] && export SDKROOT="$SDK"
swift build >/dev/null
scripts/assemble-bundle.sh "$(swift build --show-bin-path)/NotificationNanny" "$APP" "$(tr -d '[:space:]' < VERSION)" >/dev/null
swiftc -O -swift-version 5 -o "$OUT/lab" scripts/panel-lab/lab.swift

BACKUP=$OUT/defaults-backup.plist
# NN_SET="key=YES key2=NO" turns on more boolean settings for the run; restored the same way.
EXTRA=(${NN_SET:-})
KEYS=(customNotificationCenter lastBinaryMtime)
for kv in ${EXTRA[@]+"${EXTRA[@]}"}; do KEYS+=("${kv%%=*}"); done
defaults export "$DOMAIN" "$BACKUP"
NN_PID=""
restore() {
    set +e
    if [[ -n "$NN_PID" ]]; then kill "$NN_PID" 2>/dev/null; wait "$NN_PID" 2>/dev/null; fi
    "$OUT/lab" host >/dev/null && "$NOTIFY/watch" --close-all >/dev/null 2>&1
    for a in Alpha Bravo Charlie; do "$NOTIFY/Lab $a.app/Contents/MacOS/notifier" --clear >/dev/null 2>&1; done
    python3 - "$DOMAIN" "$BACKUP" "${KEYS[@]}" <<'PY'
import datetime, plistlib, subprocess, sys
domain, backup, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
saved = plistlib.load(open(backup, "rb"))
for key in keys:
    value = saved.get(key)
    if value is None:
        subprocess.run(["defaults", "delete", domain, key], capture_output=True)
    elif isinstance(value, bool):
        subprocess.run(["defaults", "write", domain, key, "-bool", "YES" if value else "NO"], check=True)
    elif isinstance(value, datetime.datetime):
        subprocess.run(["defaults", "write", domain, key, "-date", value.strftime("%Y-%m-%d %H:%M:%S +0000")], check=True)
    else:
        subprocess.run(["defaults", "write", domain, key, f"<real>{value!r}</real>" if isinstance(value, float) else str(value)], check=True)
now = plistlib.loads(subprocess.run(["defaults", "export", domain, "-"], capture_output=True, check=True).stdout)
def same(a, b):
    if isinstance(a, datetime.datetime) and isinstance(b, datetime.datetime):
        return abs((a - b).total_seconds()) < 1
    return a == b
bad = [k for k in keys if not same(now.get(k), saved.get(k))]
others = [k for k in set(saved) | set(now) if k not in keys and not same(now.get(k), saved.get(k))]
if bad or others:
    print(f"WARNING: settings differ after the run: {bad + others}; the backup is {backup}", file=sys.stderr)
    sys.exit(1)
print("settings restored and checked")
PY
}
trap restore EXIT

defaults write "$DOMAIN" customNotificationCenter -bool YES
for kv in ${EXTRA[@]+"${EXTRA[@]}"}; do defaults write "$DOMAIN" "${kv%%=*}" -bool "${kv#*=}"; done
env NN_LAB=1 NN_LAB_PANEL_FILTER="${PANEL_FILTER-Lab }" NN_LAB_PANEL_APPEARANCE="${PANEL_APPEARANCE:-}" NN_LOG_DIR="$PWD/$OUT/logs" NN_LOG_STDERR=1 \
    "$APP/Contents/MacOS/NotificationNanny" > "$OUT/app.log" 2>&1 &
NN_PID=$!
sleep 3
if ! grep -q "Observer started" "$OUT/app.log"; then
    echo "The build isn't observing Notification Center (no Accessibility for $APP?):" >&2
    tail -5 "$OUT/app.log" >&2
    exit 1
fi

for step in "$@"; do
    kind=${step%%:*}; arg=${step#*:}
    echo "-- $step"
    case "$kind" in
        post)   app=${arg%%:*}; "$NOTIFY/Lab $app.app/Contents/MacOS/notifier" "${arg#*:}" "Panel lab" ;;
        open|clock) "$OUT/lab" clock ;;
        clock2) "$NOTIFY/watch" --click-clock 2 ;;
        shut)   "$OUT/lab" shut ;;
        widget) "$OUT/lab" ui-widget "$NN_PID" || echo "   widget click failed" ;;
        apps)   for b in $arg; do pgrep -xq "$b" && echo "   $b running" || echo "   $b not running"; done ;;
        scroll) "$OUT/lab" ui-scroll "$NN_PID" ;;
        state)  "$OUT/lab" ui-state "$NN_PID" ;;
        count)  "$OUT/lab" ui-count "$NN_PID" ;;
        shot)   id=$("$OUT/lab" ui-winid "$NN_PID") && screencapture -x -o -l "$id" "$OUT/$arg.png" && echo "   $OUT/$arg.png" ;;
        click)  "$OUT/lab" ui-click "$NN_PID" "$arg" || echo "   click failed" ;;
        close)  "$OUT/lab" ui-close "$NN_PID" "$arg" || echo "   close failed" ;;
        button) "$OUT/lab" ui-button "$NN_PID" "$arg" || echo "   button failed" ;;
        wait)   sleep "$arg" ;;
        *)      echo "   unknown step" ;;
    esac
done
echo "-- app log (Panel)"
grep -E '\[Panel\]|Panel' "$OUT/app.log" | tail -12 || true
