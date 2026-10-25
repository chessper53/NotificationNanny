#!/usr/bin/env bash
# Runs the panel lab experiments (see lab.swift) on this Mac.
#
#   scripts/panel-lab/run.sh [experiment...]    default: all of them
#
# Posts two Lab notifications per lab app (build them with notify-lab/build.sh),
# opens and closes the Notification Center panel several times, and clears the
# Lab notifications at the end. The flash runs film only the strip where the
# panel opens, analyse it as numbers, and delete the recording.
set -euo pipefail
cd "$(dirname "$0")/../.."

SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d "$SDK" ]] && export SDKROOT="$SDK"
OUT=build/panel-lab
mkdir -p "$OUT"
swiftc -O -swift-version 5 -o "$OUT/lab" scripts/panel-lab/lab.swift

if pgrep -x NotificationNanny >/dev/null; then
    echo "NotificationNanny is running; quit it first, it moves the window measured here." >&2
    exit 1
fi

NOTIFY=build/notify-lab
post() { "$NOTIFY/Lab $1.app/Contents/MacOS/notifier" "$2" "$3"; }
seed() { for i in $(seq 1 "${1:-2}"); do for a in Alpha Bravo Charlie; do post "$a" "Lab row $a $i" "Panel lab $i"; done; done; sleep 2; }
clear_lab() { for a in Alpha Bravo Charlie; do "$NOTIFY/Lab $a.app/Contents/MacOS/notifier" --clear; done; }
trap clear_lab EXIT

# Points: where the panel opens on the main display.
read -r W H < <(osascript -l JavaScript -e 'ObjC.import("AppKit"); var f=$.NSScreen.screens.objectAtIndex(0).frame; f.size.width+" "+f.size.height')
REGION="$(( ${W%.*} - 760 )),0,760,${H%.*}"

flash() {
    local mode=$1 mov="$OUT/flash-$1.mov"
    rm -f "$mov"
    screencapture -x -V 4 -R "$REGION" "$mov" &
    local rec=$!
    sleep 1.2
    "$OUT/lab" flash "$mode" || true
    wait "$rec" || true
    if [[ -s "$mov" ]]; then python3 scripts/panel-lab/flash.py "$mov"; else echo "flash: no recording"; fi
    rm -f "$mov"
}

experiments=("$@")
[[ ${#experiments[@]} -eq 0 ]] && experiments=(uuid flash-native flash-react flash-prepark tap skin actions)

for x in "${experiments[@]}"; do
    echo "==> $x"
    case "$x" in
        uuid)          seed; "$OUT/lab" uuid ;;
        flash-native)  flash native ;;
        flash-react)   flash react ;;
        # Needs NC's window to exist, so a Lab banner has to be up.
        flash-prepark) post Alpha "Lab prepark" "Keeps a window to park"; sleep 1.5; flash prepark ;;
        prepark-only)  post Alpha "Lab prepark" "Keeps a window to park"; sleep 1.5; "$OUT/lab" flash prepark ;;
        tap)           "$OUT/lab" tap ;;
        skin)          seed 12; "$OUT/lab" skin ;;
        list)          seed 3; "$OUT/lab" list ;;
        actions)       seed; "$OUT/lab" actions ;;
        *)             echo "unknown experiment $x" ;;
    esac
    sleep 1
done
