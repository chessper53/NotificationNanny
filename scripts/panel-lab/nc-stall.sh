#!/usr/bin/env bash
# Temporarily pause Notification Center after a banner arrives; always resume it. See docs/LABS.md.
NC=$(pgrep -x NotificationCenter); [[ -n "$NC" ]] || exit 1
( sleep $(( ${1:-3} + 3 )); kill -CONT "$NC" 2>/dev/null ) &
trap 'kill -CONT "$NC" 2>/dev/null' EXIT
osascript -e 'display notification "Lab stall test" with title "Lab stall"'
sleep "${2:-0.4}"
kill -STOP "$NC"; sleep "${1:-3}"; kill -CONT "$NC"
sleep 3
