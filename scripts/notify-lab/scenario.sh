#!/usr/bin/env bash
# Runs one live scenario against a NotificationNanny build and checks where the
# banners end up.
#
#   scripts/notify-lab/scenario.sh [options] <post>...
#
#   <post>               delay:App[:title], e.g. 0:Alpha 0.6:Bravo 0.6:Charlie
#                        (delay in seconds after the previous post; App is one
#                        of the lab apps: Alpha, Bravo, Charlie)
#                        delay:Script[:title] posts through osascript instead,
#                        which macOS shows as a Temporary Script Editor banner
#                        delay:close:App closes that lab app's banner
#   --position P         bottomRight (default), topRight, middleLeft, ...
#   --x-offset N         placement offset in points (default 0)
#   --y-offset N
#   --auto-dismiss S     seconds, 0 = system default (default 0)
#   --custom             use the custom banner (via a 1.002 scale, which looks
#                        the same as 1 but switches the custom banner on)
#   --scale F            custom banner scale (implies the custom banner)
#   --newest-at-bottom   custom pile order: newest at the bottom
#   --seconds N          how long to watch (default 10)
#   --app PATH           the .app to run (default build/NotificationNanny.app)
#   --oslog              also capture the app's debug log (last-oslog.txt); this
#                        slows the app down noticeably, so not for timing runs
#   --keep-existing      leave banners already on screen instead of closing them
#                        first, to test a pile that predates the app
#
# The app is run straight from this shell, so it shares the shell's
# Accessibility permission and a rebuild doesn't need a new grant. The settings
# it touches are backed up before, written back key by key on exit whatever
# happens, and checked; a mismatch is reported loudly. The lab apps must be
# built (build.sh) and allowed to notify; set them to Persistent in System
# Settings > Notifications to get banners that pile up.
#
# The app's session log lands in build/notify-lab/last-app.log, the watcher's
# timeline in last-run.txt, and its debug log (sweep timings among it) in
# last-oslog.txt with --oslog. The app's CPU time and memory over the watch are
# printed last.
#
# Exit status: the watcher's failed check count.
set -euo pipefail
cd "$(dirname "$0")/../.."

DOMAIN=com.notificationnanny.app
LAB=build/notify-lab
APP=build/NotificationNanny.app
POSITION=bottomRight X=0 Y=0 AUTO=0 CUSTOM=0 SCALE=1 WATCH_SECS=10 KEEP=0 OSLOG=0 NEWEST_BOTTOM=0
POSTS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --position) POSITION=$2; shift 2 ;;
        --x-offset) X=$2; shift 2 ;;
        --y-offset) Y=$2; shift 2 ;;
        --auto-dismiss) AUTO=$2; shift 2 ;;
        --custom) CUSTOM=1; [[ $SCALE == 1 ]] && SCALE=1.002; shift ;;
        --scale) SCALE=$2; CUSTOM=1; shift 2 ;;
        --seconds) WATCH_SECS=$2; shift 2 ;;
        --app) APP=$2; shift 2 ;;
        --keep-existing) KEEP=1; shift ;;
        --oslog) OSLOG=1; shift ;;
        --newest-at-bottom) NEWEST_BOTTOM=1; shift ;;
        *) POSTS+=("$1"); shift ;;
    esac
done
# No posts is fine: an idle run measures the baseline.

BACKUP=$LAB/defaults-backup.plist
# Everything this script writes. Only these are restored, one by one through
# `defaults write`: `defaults import` bypasses the preferences cache and a
# cached copy can win afterwards, which once left a test configuration behind.
# lastBinaryMtime is stamped by the app itself on every launch.
KEYS=(placementsByDisplayID targetDisplayID autoDismissSeconds redactBannerContent bannerScale
      hasBannerColor bannerAnimation followActiveScreen holdWhileAsleep pauseWhileStreaming pauseDuringFocus
      lastBinaryMtime newestBannerAtBottom)
NN_MATCH="\.app/Contents/MacOS/NotificationNanny"
NN_PID=""
# Only the instance this script started is ever stopped.
quit_nn() {
    [[ -n "$NN_PID" ]] || return 0
    kill "$NN_PID" 2>/dev/null || true
    wait "$NN_PID" 2>/dev/null || true
    NN_PID=""
}
restore() {
    set +e
    quit_nn
    "$LAB/watch" --close-all >/dev/null 2>&1
    # And what they left in Notification Center's history.
    for app in "$LAB"/Lab\ *.app; do "$app/Contents/MacOS/notifier" --clear >/dev/null 2>&1; done
    python3 - "$DOMAIN" "$BACKUP" "${KEYS[@]}" <<'PY'
import datetime, plistlib, subprocess, sys
domain, backup, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
saved = plistlib.load(open(backup, "rb"))
def write(key, value):
    if isinstance(value, bool):    args = ["-bool", "YES" if value else "NO"]
    elif isinstance(value, int):   args = ["-int", str(value)]
    elif isinstance(value, float): args = ["-float", repr(value)]
    elif isinstance(value, bytes): args = ["-data", value.hex()]
    elif isinstance(value, datetime.datetime):
        args = ["-date", value.strftime("%Y-%m-%d %H:%M:%S +0000")]
    else:                          args = ["-string", str(value)]
    subprocess.run(["defaults", "write", domain, key, *args], check=True)
for key in keys:
    if key in saved: write(key, saved[key])
    else: subprocess.run(["defaults", "delete", domain, key], capture_output=True)
now = plistlib.loads(subprocess.run(["defaults", "export", domain, "-"], capture_output=True, check=True).stdout)
def same(a, b):
    # -date has whole seconds, the app stores microseconds.
    if isinstance(a, datetime.datetime) and isinstance(b, datetime.datetime):
        return abs((a - b).total_seconds()) < 1
    return a == b
bad = [k for k in keys if not same(now.get(k), saved.get(k))]
if bad:
    print(f"WARNING: settings NOT restored for {bad}; the backup is {backup}", file=sys.stderr)
    sys.exit(1)
print("settings restored")
PY
}
if "$LAB/watch" --locked; then
    echo "The screen is locked; macOS shows no banners until it is unlocked." >&2
    exit 66
fi

# Another NotificationNanny would fight this one over the banners, and it is
# not this script's to quit.
if pgrep -f "$NN_MATCH" >/dev/null; then
    echo "NotificationNanny is already running; quit it first:" >&2
    pgrep -lf "$NN_MATCH" >&2
    exit 65
fi
defaults export "$DOMAIN" "$BACKUP"
trap restore EXIT

[[ $KEEP == 1 ]] || "$LAB/watch" --close-all >/dev/null

# Same placement on every display, so it doesn't matter which one gets the banner.
PLACEMENTS=$("$LAB/watch" --screens | awk -v p="$POSITION" -v x="$X" -v y="$Y" '
    BEGIN { printf "{" }
    { if (NR > 1) printf ","; printf "\"%s\":{\"position\":\"%s\",\"xOffset\":%s,\"yOffset\":%s}", $1, p, x, y }
    END { printf "}" }')
defaults write "$DOMAIN" placementsByDisplayID -data "$(printf '%s' "$PLACEMENTS" | xxd -p | tr -d '\n')"
defaults write "$DOMAIN" targetDisplayID -int 0
defaults write "$DOMAIN" autoDismissSeconds -float "$AUTO"
defaults write "$DOMAIN" redactBannerContent -bool NO
defaults write "$DOMAIN" newestBannerAtBottom -bool $([[ $NEWEST_BOTTOM == 1 ]] && echo YES || echo NO)
defaults write "$DOMAIN" bannerScale -float "$SCALE"
defaults write "$DOMAIN" hasBannerColor -bool NO
defaults write "$DOMAIN" bannerAnimation -string Default
for key in followActiveScreen holdWhileAsleep pauseWhileStreaming pauseDuringFocus; do
    defaults write "$DOMAIN" "$key" -bool NO
done

echo "==> $POSITION offset ($X,$Y), auto-dismiss ${AUTO}s, $([[ $CUSTOM == 1 ]] && echo "custom, scale ${SCALE}" || echo native)$([[ $NEWEST_BOTTOM == 1 ]] && echo ", newest at the bottom")"
NN_LOG_STDERR=1 NN_TIMING=1 "$APP/Contents/MacOS/NotificationNanny" > "$LAB/last-app.log" 2>&1 &
NN_PID=$!
sleep 3

# CPU seconds from ps's [[dd-]hh:]mm:ss.cc
cpu_seconds() { ps -o time= -p "$1" | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; printf "%.2f", s }'; }
rss_mb() { ps -o rss= -p "$1" | awk '{ printf "%.1f", $1 / 1024 }'; }
LOG_PID=""
if [[ $OSLOG == 1 ]]; then
    /usr/bin/log stream --level debug --style compact \
        --predicate "subsystem == \"com.notificationnanny\" AND processID == $NN_PID" > "$LAB/last-oslog.txt" 2>&1 &
    LOG_PID=$!
fi
CPU0=$(cpu_seconds "$NN_PID"); RSS0=$(rss_mb "$NN_PID"); WIN0=$("$LAB/watch" --windows "$NN_PID")

"$LAB/watch" "$WATCH_SECS" > "$LAB/last-run.txt" 2>&1 &
WATCH_PID=$!
sleep 0.3
for spec in ${POSTS[@]+"${POSTS[@]}"}; do
    IFS=: read -r delay app title <<< "$spec"
    sleep "$delay"
    case $app in
        close)  "$LAB/watch" --close-app "$title" >/dev/null & ;;
        Script) osascript -e "display notification \"Body from Script\" with title \"${title:-Script title}\"" & ;;
        *)      "$LAB/Lab $app.app/Contents/MacOS/notifier" "${title:-$app title}" "Body from $app" & ;;
    esac
done

set +e
wait "$WATCH_PID"
STATUS=$?
set -e
CPU1=$(cpu_seconds "$NN_PID"); RSS1=$(rss_mb "$NN_PID"); WIN1=$("$LAB/watch" --windows "$NN_PID")
if "$LAB/watch" --locked; then
    echo "INVALID: the screen locked during the run, so banners were only queued" >&2
    STATUS=66
fi
[[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null || true
cat "$LAB/last-run.txt"
echo "app: $(awk -v a="$CPU0" -v b="$CPU1" 'BEGIN { printf "%.2f", b - a }')s CPU over ${WATCH_SECS}s, memory ${RSS0} MB -> ${RSS1} MB, windows ${WIN0} -> ${WIN1}"
exit "$STATUS"
