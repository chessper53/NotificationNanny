#!/usr/bin/env bash
# scripts/panel-lab/nc-stall.sh [seconds] [delay]: pauses Notification Center for $1 seconds (default 3) right after a banner arrives,
# so sweeps meet a Notification Center that doesn't answer. Always resumed.
NC=$(pgrep -x NotificationCenter); [[ -n "$NC" ]] || exit 1
( sleep $(( ${1:-3} + 3 )); kill -CONT "$NC" 2>/dev/null ) &
trap 'kill -CONT "$NC" 2>/dev/null' EXIT
osascript -e 'display notification "Lab stall test" with title "Lab stall"'
sleep "${2:-0.4}"
kill -STOP "$NC"; sleep "${1:-3}"; kill -CONT "$NC"
sleep 3
