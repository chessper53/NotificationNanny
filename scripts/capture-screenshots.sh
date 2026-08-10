#!/usr/bin/env bash
# Captures a fresh screenshot of each settings tab (Position, Banner, Exceptions,
# Presets, General, Help) into docs/screenshots/, and copies them into
# site/assets/screenshots/ for the landing page. README.md and site/index.html
# both reference these by filename, so re-running this script and committing the
# result is the entire "carry the screenshots over" step for a release — no
# manual capture-and-reupload dance.
#
# Requirements:
#   - NotificationNanny already built and running, with Accessibility permission
#     already granted (./dev.sh, or --launch below).
#   - One-time Automation permission for whichever terminal runs this script, to
#     let it drive the app's UI via System Events (System Settings → Privacy &
#     Security → Automation → <your terminal> → System Events). macOS prompts
#     for this automatically the first time you run the script interactively.
#
# Usage:
#   ./scripts/capture-screenshots.sh            # capture against an already-running instance
#   ./scripts/capture-screenshots.sh --launch    # kill, build, launch, then capture

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="NotificationNanny"
WINDOW_TITLE="NotificationNanny Settings"
OUT_DIR="docs/screenshots"
SITE_DIR="site/assets/screenshots"
TITLEBAR_HEIGHT=32

TABS=(Position Banner Exceptions Presets General Help)
FILES=(position banner exceptions presets general help)
# Sidebar buttons don't expose their label as an accessible name/description/
# title, and the label Text isn't exposed as a separately-queryable child
# AXStaticText either (confirmed by dumping both) — .buttonStyle(.plain) with
# a custom HStack{Image;Text} label just doesn't surface searchable text here.
# So: click by fixed position in the sidebar VStack instead. Order is exactly
# SettingsView.swift's sidebarItem(...) call order: Position, Exceptions,
# Banner, Presets, General, Backup, Diagnostics, Help (then Disable/Quit) — if
# that file's sidebar order ever changes, update this mapping to match.
INDICES=(1 3 2 4 5 8)

if [[ "${1:-}" == "--launch" ]]; then
    echo "==> Building and launching..."
    ./dev.sh
    sleep 3
fi

if ! pgrep -x "$APP_NAME" > /dev/null; then
    echo "error: $APP_NAME is not running. Launch it first, or pass --launch." >&2
    exit 1
fi

mkdir -p "$OUT_DIR" "$SITE_DIR"

find_window_bounds() {
    # Matching by title (kCGWindowName) doesn't work unless the calling process
    # has Screen Recording permission — without it, macOS redacts window titles
    # from CGWindowListCopyWindowInfo entirely (the key is just absent), even
    # though bounds/layer/alpha are still reported. Match by the Settings
    # window's fixed content width (660, set explicitly in Swift) instead —
    # that's stable and doesn't require an extra permission. The only other
    # window this process owns is the unused Settings{EmptyView()} scene's
    # window, which is 500x500 and won't match.
    python3 -c "
import Quartz
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID):
    if w.get('kCGWindowOwnerName') == '$APP_NAME':
        b = w['kCGWindowBounds']
        if int(b['Width']) == 660:
            print(int(b['X']), int(b['Y']), int(b['Width']), int(b['Height']))
            break
"
}

dump_all_windows() {
    echo "---- all windows currently owned by $APP_NAME ----" >&2
    python3 -c "
import Quartz
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID):
    if w.get('kCGWindowOwnerName') == '$APP_NAME':
        print('  name=%r layer=%r alpha=%r bounds=%r' % (
            w.get('kCGWindowName'), w.get('kCGWindowLayer'), w.get('kCGWindowAlpha'), w.get('kCGWindowBounds')))
" >&2
    echo "---------------------------------------------------" >&2
}

wait_for_window() {
    local tries=0
    while [[ -z "$(find_window_bounds)" ]]; do
        tries=$((tries + 1))
        if [[ $((tries % 4)) -eq 0 ]]; then
            echo "    ...still waiting ($((tries / 2))s) — dumping what's visible so far:" >&2
            dump_all_windows
        fi
        if [[ $tries -gt 60 ]]; then
            echo "error: $WINDOW_TITLE never matched after 30s. If the window above shows the" >&2
            echo "right title but this still fails, it's a lookup bug, not a timing issue —" >&2
            echo "send me that dump output." >&2
            exit 1
        fi
        sleep 0.5
    done
    echo "    found window after $((tries / 2))s"
}

echo "==> Opening Settings window..."
osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to click menu bar item 1 of menu bar 2" \
    || { echo "error: couldn't click the menu bar icon — is Automation permission granted?" >&2; exit 1; }
sleep 0.3
osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to set frontmost to true" || true
wait_for_window

# Move to a fixed, positive-coordinate position on the primary display before
# capturing: screencapture -R has been flaky with negative-X windows (secondary
# displays positioned left of the primary), and a fixed position also makes
# every capture consistent regardless of which screen the app happened to open on.
osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to set position of window \"$WINDOW_TITLE\" to {100, 100}" 2>/dev/null || true
sleep 0.3

click_tab_by_index() {
    osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to click button $1 of group 1 of window \"$WINDOW_TITLE\""
}

capture_window() {
    local bounds
    bounds="$(find_window_bounds)"
    if [[ -z "$bounds" ]]; then
        echo "error: couldn't find the $WINDOW_TITLE window" >&2
        exit 1
    fi
    read -r x y w h <<< "$bounds"
    screencapture -R"${x},$((y + TITLEBAR_HEIGHT)),${w},$((h - TITLEBAR_HEIGHT))" -x "$1"
}

for i in "${!TABS[@]}"; do
    label="${TABS[$i]}"
    file="${FILES[$i]}"
    idx="${INDICES[$i]}"
    echo "==> Capturing $label (button $idx)..."
    click_tab_by_index "$idx"
    sleep 0.5
    capture_window "$OUT_DIR/${file}.png"
    cp "$OUT_DIR/${file}.png" "$SITE_DIR/${file}.png"
done

echo "==> Done. Screenshots written to $OUT_DIR/ and $SITE_DIR/."
echo "==> Review them, then commit: git add $OUT_DIR $SITE_DIR"
