#!/usr/bin/env bash
# Run a live banner scenario and return its failed check count. See docs/LABS.md.
# Restore touched settings individually on exit and isolate session logs from the installed app.
set -euo pipefail
cd "$(dirname "$0")/../.."

DOMAIN=com.notificationnanny.app
LAB=build/notify-lab
APP=build/NotificationNanny.app
POSITION=bottomRight X=0 Y=0 AUTO=0 CUSTOM=0 SCALE=1 WATCH_SECS=10 KEEP=0 OSLOG=0 NEWEST_BOTTOM=0 DISPLAY_N=0 NC_FOLLOW=0 FOCUS=0
POSTS=()
LAB_GROUPS=()
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
        --display) DISPLAY_N=$2; shift 2 ;;
        --nc-follow) NC_FOLLOW=1; shift ;;
        --focus) FOCUS=1; shift ;;
        --group) LAB_GROUPS+=("$2"); shift 2 ;;
        *) POSTS+=("$1"); shift ;;
    esac
done
# No posts is fine: an idle run measures the baseline.

BACKUP=$LAB/defaults-backup.plist
FOCUS_FILE=$LAB/focus-assertions.json
# The layout FocusModeMonitor reads: any record at all means a Focus is on.
set_focus() {
    if [[ $1 == on ]]; then records='[{"lab": true}]'; else records='[]'; fi
    printf '{"data":[{"storeAssertionRecords":%s}]}\n' "$records" > "$FOCUS_FILE.tmp"
    mv "$FOCUS_FILE.tmp" "$FOCUS_FILE"
}
# Restore keys individually because defaults import bypasses the preferences cache.
# Include lastBinaryMtime, which the app writes on launch.
KEYS=(placementsByDisplayID targetDisplayID targetDisplayUUID autoDismissSeconds redactBannerContent bannerScale
      hasBannerColor bannerAnimation followActiveScreen holdWhileAsleep pauseWhileStreaming pauseDuringFocus
      lastBinaryMtime newestBannerAtBottom appGroups avoidNCPanel)
NN_MATCH="\.app/Contents/MacOS/NotificationNanny"
NN_PID=""
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
    for app in "$LAB"/Lab\ *.app; do "$app/Contents/MacOS/notifier" --clear >/dev/null 2>&1; done
    python3 - "$DOMAIN" "$BACKUP" "${KEYS[@]}" <<'PY'
import datetime, plistlib, subprocess, sys
domain, backup, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
saved = plistlib.load(open(backup, "rb"))
def write(key, value):
    if isinstance(value, bool):    args = ["-bool", "YES" if value else "NO"]
    elif isinstance(value, int):   args = ["-int", str(value)]
    # A plist real preserves double precision that the floating point command option would lose.
    elif isinstance(value, float): args = [f"<real>{value!r}</real>"]
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
    # Date command writes lose subseconds; the app stores microseconds.
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

# Refuse competing instances rather than stopping an app the user launched.
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
if [[ $DISPLAY_N == 0 ]]; then
    defaults write "$DOMAIN" targetDisplayID -int 0
    defaults delete "$DOMAIN" targetDisplayUUID 2>/dev/null || true
else
    read -r uuid _ did <<< "$("$LAB/watch" --screens | sed -n "${DISPLAY_N}p")"
    [[ -n "${did:-}" ]] || { echo "no screen $DISPLAY_N" >&2; exit 64; }
    defaults write "$DOMAIN" targetDisplayID -int "$did"
    defaults write "$DOMAIN" targetDisplayUUID -string "$uuid"
fi
defaults write "$DOMAIN" autoDismissSeconds -float "$AUTO"
defaults write "$DOMAIN" redactBannerContent -bool NO
defaults write "$DOMAIN" newestBannerAtBottom -bool $([[ $NEWEST_BOTTOM == 1 ]] && echo YES || echo NO)
defaults write "$DOMAIN" bannerScale -float "$SCALE"
defaults write "$DOMAIN" hasBannerColor -bool NO
defaults write "$DOMAIN" bannerAnimation -string Default
for key in followActiveScreen holdWhileAsleep pauseWhileStreaming pauseDuringFocus; do
    defaults write "$DOMAIN" "$key" -bool NO
done
defaults write "$DOMAIN" avoidNCPanel -bool $([[ $NC_FOLLOW == 1 ]] && echo NO || echo YES)
# Exception groups as AppSettings stores them: JSON, each on every display.
GROUPS_JSON="["
for spec in ${LAB_GROUPS[@]+"${LAB_GROUPS[@]}"}; do
    IFS=: read -r app pos mode <<< "$spec"
    [[ $GROUPS_JSON == "[" ]] || GROUPS_JSON+=","
    GROUPS_JSON+="{\"id\":\"$(uuidgen)\",\"name\":\"Lab $app\",\"appNames\":[\"Lab $app\"],"
    GROUPS_JSON+="\"placement\":{\"position\":\"$pos\",\"xOffset\":0,\"yOffset\":0},\"targetDisplayID\":0${mode:+,\"bannerMode\":\"$mode\"}}"
done
GROUPS_JSON+="]"
defaults write "$DOMAIN" appGroups -data "$(printf '%s' "$GROUPS_JSON" | xxd -p | tr -d '\n')"
FOCUS_ENV=()
if [[ $FOCUS == 1 ]]; then
    defaults write "$DOMAIN" pauseDuringFocus -bool YES
    set_focus on
    FOCUS_ENV=(NN_FOCUS_ASSERTIONS="$FOCUS_FILE")
fi

echo "==> $POSITION offset ($X,$Y), auto-dismiss ${AUTO}s, $([[ $CUSTOM == 1 ]] && echo "custom, scale ${SCALE}" || echo native)$([[ $NEWEST_BOTTOM == 1 ]] && echo ", newest at the bottom")$([[ $FOCUS == 1 ]] && echo ", fake Focus on")"
env ${FOCUS_ENV[@]+"${FOCUS_ENV[@]}"} NN_LAB=1 NN_LOG_DIR="$PWD/$LAB/logs" NN_LOG_STDERR=1 NN_TIMING=1 "$APP/Contents/MacOS/NotificationNanny" > "$LAB/last-app.log" 2>&1 &
NN_PID=$!
sleep 3

# Convert the process CPU time fields to seconds.
cpu_seconds() { ps -o time= -p "$1" | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; printf "%.2f", s }'; }
rss_mb() { ps -o rss= -p "$1" | awk '{ printf "%.1f", $1 / 1024 }'; }
LOG_PID=""
if [[ $OSLOG == 1 ]]; then
    /usr/bin/log stream --level debug --style compact \
        --predicate "subsystem == \"com.notificationnanny\" AND processID == $NN_PID" > "$LAB/last-oslog.txt" 2>&1 &
    LOG_PID=$!
fi
CPU0=$(cpu_seconds "$NN_PID"); RSS0=$(rss_mb "$NN_PID"); WIN0=$("$LAB/watch" --windows "$NN_PID")

: > "$LAB/last-steps.txt"
"$LAB/watch" "$WATCH_SECS" > "$LAB/last-run.txt" 2>&1 &
WATCH_PID=$!
sleep 0.3
for spec in ${POSTS[@]+"${POSTS[@]}"}; do
    IFS=: read -r delay app title <<< "$spec"
    sleep "$delay"
    case $app in
        close)  "$LAB/watch" --close-app "$title" >/dev/null & ;;
        panel)  "$LAB/watch" --clock ;;
        clock)  "$LAB/watch" --click-clock "$title" ;;
        expand) "$LAB/watch" --expand "$title" ;;
        wake)   "$LAB/watch" --wake; echo "$(date +%T) wake" >> "$LAB/last-steps.txt" ;;
        shot)   screencapture -x "$LAB/$title.png"; echo "$(date +%T) screenshot $title" >> "$LAB/last-steps.txt" ;;
        focus)  set_focus "$title"; echo "$(date +%T) fake Focus $title" >> "$LAB/last-steps.txt" ;;
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
