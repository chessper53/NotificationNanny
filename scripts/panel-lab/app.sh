#!/usr/bin/env bash
# Drive a custom panel with Lab notifications only and restore touched settings on exit.
# Commands and environment options are in docs/LABS.md.
set -euo pipefail
cd "$(dirname "$0")/../.."

DOMAIN=com.notificationnanny.app
OUT=build/panel-lab
NOTIFY=build/notify-lab
APP=build/NotificationNanny.app
NN_MATCH="\.app/Contents/MacOS/NotificationNanny"
mkdir -p "$OUT"

# NN_ATTACH drives an existing app with its own Screen Recording grant; its caller owns settings
# restoration.
ATTACH=${NN_ATTACH:-}
if [[ -z "$ATTACH" ]] && pgrep -f "$NN_MATCH" >/dev/null; then
    echo "NotificationNanny is already running; quit it first." >&2
    exit 65
fi

SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d "$SDK" ]] && export SDKROOT="$SDK"
if [[ -z "$ATTACH" ]]; then
    swift build >/dev/null
    DEV_SIGNING=1 scripts/assemble-bundle.sh "$(swift build --show-bin-path)/NotificationNanny" "$APP" "$(tr -d '[:space:]' < VERSION)" >/dev/null
fi
swiftc -O -swift-version 5 -o "$OUT/lab" scripts/panel-lab/lab.swift

BACKUP=$OUT/defaults-backup.plist
# NN_SET supplies additional settings that are backed up and restored.
EXTRA=(${NN_SET:-})
KEYS=(customNotificationCenter lastBinaryMtime)
for kv in ${EXTRA[@]+"${EXTRA[@]}"}; do KEYS+=("${kv%%=*}"); done
defaults export "$DOMAIN" "$BACKUP"
NN_PID=""
restore() {
    set +e
    if [[ -n "$NN_PID" && -z "$ATTACH" ]]; then kill "$NN_PID" 2>/dev/null; wait "$NN_PID" 2>/dev/null; fi
    # Close the native panel before restoring its window so it does not remain visible after the
    # run.
    "$OUT/lab" shut >/dev/null
    # Restore the parked host before stopping the app so later banners stay visible.
    "$OUT/lab" unpark
    # KEEP_LAB retains Lab notifications for a subsequent run.
    if [[ -z "${KEEP_LAB:-}" ]]; then
        "$OUT/lab" host >/dev/null && "$NOTIFY/watch" --close-all >/dev/null 2>&1
        for a in Alpha Bravo Charlie; do "$NOTIFY/Lab $a.app/Contents/MacOS/notifier" --clear >/dev/null 2>&1; done
    fi
    [[ -n "$ATTACH" ]] && return
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
    elif isinstance(value, int):
        subprocess.run(["defaults", "write", domain, key, "-integer", str(value)], check=True)
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
# Convert signals to exit so the restoration trap always runs.
trap 'exit 130' INT TERM

if [[ -n "$ATTACH" ]]; then
    NN_PID=$ATTACH
else
defaults write "$DOMAIN" customNotificationCenter -bool YES
for kv in ${EXTRA[@]+"${EXTRA[@]}"}; do
    k=${kv%%=*}; v=${kv#*=}
    case "$v" in
        YES|NO) defaults write "$DOMAIN" "$k" -bool "$v" ;;
        *[!0-9.]*) defaults write "$DOMAIN" "$k" -string "$v" ;;
        *) defaults write "$DOMAIN" "$k" -float "$v" ;;
    esac
done
env NN_LAB=1 NN_TIMING="${NN_TIMING:-}" NN_LAB_PANEL_FILTER="${PANEL_FILTER-Lab }" NN_LAB_PANEL_APPEARANCE="${PANEL_APPEARANCE:-}" NN_LOG_DIR="$PWD/$OUT/logs" NN_LOG_STDERR=1 \
    "$APP/Contents/MacOS/NotificationNanny" > "$OUT/app.log" 2>&1 &
NN_PID=$!
sleep 3
if ! grep -q "Observer started" "$OUT/app.log"; then
    echo "The build isn't observing Notification Center (no Accessibility for $APP?):" >&2
    tail -5 "$OUT/app.log" >&2
    exit 1
fi
fi

for step in "$@"; do
    kind=${step%%:*}; arg=${step#*:}
    echo "-- $step"
    case "$kind" in
        post)   app=${arg%%:*}; "$NOTIFY/Lab $app.app/Contents/MacOS/notifier" "${arg#*:}" "Panel lab" ;;
        postact) app=${arg%%:*}; "$NOTIFY/Lab $app.app/Contents/MacOS/notifier" "${arg#*:}" "Panel lab" --actions ;;
        postreply) app=${arg%%:*}; "$NOTIFY/Lab $app.app/Contents/MacOS/notifier" "${arg#*:}" "Panel lab" --reply ;;
        postlong) app=${arg%%:*}; "$NOTIFY/Lab $app.app/Contents/MacOS/notifier" "${arg#*:}" "A long body that goes on and on so the text wraps over several lines, to see where the button sits" --actions ;;
        hover)  "$OUT/lab" ui-hover "$NN_PID" "$arg" ;;
        type)   "$OUT/lab" type "$arg" ;;
        responses) tail -n "${arg:-3}" "$NOTIFY/responses.log" 2>/dev/null | sed 's/^/   /' ;;
        open|clock) "$OUT/lab" clock ;;
        clock2) "$NOTIFY/watch" --click-clock 2 ;;
        shut)   "$OUT/lab" shut ;;
        widget) "$OUT/lab" ui-widget "$NN_PID" || echo "   widget click failed" ;;
        wrclick) "$OUT/lab" ui-widget "$NN_PID" right || echo "   widget right click failed" ;;
        apps)   for b in $arg; do pgrep -xq "$b" && echo "   $b running" || echo "   $b not running"; done ;;
        scroll) [[ "$step" == scroll ]] && arg=""; NN_LAB_WHEEL="${WHEEL:-}" "$OUT/lab" ui-scroll "$NN_PID" $arg ;;
        state)  "$OUT/lab" ui-state "$NN_PID" ;;
        frames) "$OUT/lab" ui-frames "$NN_PID" ;;
        count)  "$OUT/lab" ui-count "$NN_PID" ;;
        shot)   id=$("$OUT/lab" ui-winid "$NN_PID") && scripts/panel-lab/shot.sh screencapture -x -o -l "$id" "$OUT/$arg.png" >/dev/null && echo "   $OUT/$arg.png" ;;
        # Mask the user's desktop with gray for transparent captures. Wait only for the backdrop
        # process, not the app.
        sshot)  r=$("$OUT/lab" ui-rect "$NN_PID") && { "$OUT/lab" backdrop "$r" 2 & bd=$!; sleep 0.8
                scripts/panel-lab/shot.sh screencapture -x -R"$r" "$OUT/$arg.png" >/dev/null; wait "$bd"; echo "   $OUT/$arg.png"; } ;;
        click)  "$OUT/lab" ui-click "$NN_PID" "$arg" || echo "   click failed" ;;
        rclick) "$OUT/lab" ui-rclick "$NN_PID" "$arg" || echo "   right click failed" ;;
        close)  "$OUT/lab" ui-close "$NN_PID" "$arg" || echo "   close failed" ;;
        button) "$OUT/lab" ui-button "$NN_PID" "$arg" || echo "   button failed" ;;
        bhover)  NN_LAB_TARGET=banners "$OUT/lab" ui-hover "$NN_PID" "$arg" ;;
        bbutton) NN_LAB_TARGET=banners "$OUT/lab" ui-button "$NN_PID" "$arg" || echo "   button failed" ;;
        bstate)  NN_LAB_TARGET=banners "$OUT/lab" ui-state "$NN_PID" ;;
        brclick) NN_LAB_TARGET=banners "$OUT/lab" ui-rclick "$NN_PID" "$arg" || echo "   right click failed" ;;
        pref)    echo "   $arg = $(defaults read "$DOMAIN" "$arg" 2>/dev/null || echo unset)" ;;
        clicktop) "$OUT/lab" ui-clicktop "$NN_PID" || echo "   click failed" ;;
        pframe)  "$OUT/lab" ui-winid "$NN_PID" frame ;;
        settings) "$OUT/lab" ui-settings "$NN_PID" || echo "   settings failed" ;;
        sdrag)   "$OUT/lab" ui-sdrag "$NN_PID" "$arg" || echo "   drag failed" ;;
        menu)    [[ "$step" == menu ]] && arg=""; "$OUT/lab" ui-menu "$NN_PID" "$arg" || echo "   menu failed" ;;
        film)   r=$("$OUT/lab" ui-rect "$NN_PID")
                "$OUT/lab" backdrop "$r" "$((arg + 2))" 20 & FILM_BD=$!; sleep 0.8
                screencapture -x -V "$arg" -R"$r" "$OUT/film.mov" & FILM_REC=$!; sleep 0.5 ;;
        filmend) wait "$FILM_REC"; wait "$FILM_BD"; python3.14 scripts/panel-lab/settle.py "$OUT/film.mov"; rm -f "$OUT/film.mov" ;;
        wait)   sleep "$arg" ;;
        *)      echo "   unknown step" ;;
    esac
done
echo "-- app log (Panel)"
grep -E '\[Panel\]|Panel' "$OUT/app.log" | tail -12 || true
