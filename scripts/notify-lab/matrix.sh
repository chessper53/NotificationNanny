#!/usr/bin/env bash
# Runs the pile scenarios one after another and prints a summary.
#
#   scripts/notify-lab/matrix.sh [--app PATH] [name...]
#
# With names, only those scenarios run. Each leaves its timeline in
# build/notify-lab/matrix/<name>.txt and the app's log next to it.
set -uo pipefail
cd "$(dirname "$0")/../.."

APP=build/NotificationNanny.app
if [[ ${1:-} == --app ]]; then APP=$2; shift 2; fi
OUT=build/notify-lab/matrix
mkdir -p "$OUT"

PILE="0:Alpha 0.8:Bravo 0.8:Charlie"
SCENARIOS=(
    "native-bottom|--seconds 6|$PILE"
    "native-offset-205|--y-offset -205 --seconds 6|$PILE"
    "native-offset-off-screen|--y-offset 300 --seconds 6|$PILE"
    "native-top|--position topRight --seconds 6|$PILE"
    "native-middle|--position middleRight --seconds 6|$PILE"
    "native-auto-dismiss|--auto-dismiss 3 --seconds 9|$PILE"
    "custom-bottom|--custom --seconds 6|$PILE"
    "custom-offset-205|--custom --y-offset -205 --seconds 6|$PILE"
    "custom-scale|--scale 1.3 --seconds 6|$PILE"
    "custom-auto-dismiss|--custom --auto-dismiss 3 --seconds 9|$PILE"
    "same-app-merge|--seconds 6|0:Alpha 0.8:Alpha:Second 0.8:Bravo"
)

failed=0
for entry in "${SCENARIOS[@]}"; do
    IFS='|' read -r name opts posts <<< "$entry"
    if [[ $# -gt 0 ]] && [[ ! " $* " == *" $name "* ]]; then continue; fi
    # shellcheck disable=SC2086
    scripts/notify-lab/scenario.sh --app "$APP" $opts $posts > "$OUT/$name.txt" 2>&1
    status=$?
    cp build/notify-lab/last-app.log "$OUT/$name.app.log" 2>/dev/null
    restored=$(grep -E "^settings restored|^WARNING" "$OUT/$name.txt" | tail -1)
    if [[ $status == 0 ]]; then verdict="ok  "; else verdict="FAIL"; failed=$((failed + 1)); fi
    printf '%s %-26s %s\n' "$verdict" "$name" "${restored:-settings state unknown}"
    grep -E "^FAIL|^        " "$OUT/$name.txt" | sed 's/^/       /'
    # The last picture the watcher saw.
    grep -v -E "^(ok|FAIL|settings|WARNING|==)|^$" "$OUT/$name.txt" | tail -r | awk '/^t=/{print; exit} {print}' | tail -r | sed 's/^/       /'
done
echo
echo "$failed failed"
exit "$failed"
