#!/usr/bin/env bash
# The real Notification Center panel and ours side by side, in Dark and Light Mode.
#
#   scripts/panel-lab/compare.sh
#
# Posts Lab notifications (a single one, a stack of three, one with buttons), then
# captures the real panel and ours, each collapsed and with the stack expanded, over the
# same gray backdrop, in both appearances (the system's is put back). Only the area of the
# Lab rows is captured: they are alerts, at the top, and the user's own history is below.
# Writes build/panel-lab/compare-<appearance>.png and compare.png.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=build/panel-lab
NOTIFY=build/notify-lab
LAB=$OUT/lab
THEME=build/banner-lab/lab
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d "$SDK" ]] && export SDKROOT="$SDK"
swiftc -O -swift-version 5 -o "$LAB" scripts/panel-lab/lab.swift
[[ -x "$THEME" ]] || { echo "build banner-lab first: scripts/banner-lab/run.sh" >&2; exit 1; }
if pgrep -f '\.app/Contents/MacOS/NotificationNanny' >/dev/null; then
    echo "NotificationNanny is running; quit it first." >&2; exit 65
fi

APPEARANCE=$(defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark && echo dark || echo light)
cleanup() {
    set +e
    "$LAB" shut >/dev/null
    "$THEME" theme "$APPEARANCE"
    "$NOTIFY/watch" --close-all >/dev/null
    for a in Alpha Bravo Charlie; do "$NOTIFY/Lab $a.app/Contents/MacOS/notifier" --clear; done
    "$LAB" unpark >/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM

post() {
    for a in Alpha Bravo Charlie; do "$NOTIFY/Lab $a.app/Contents/MacOS/notifier" --clear; done
    sleep 1.5
    "$NOTIFY/Lab Alpha.app/Contents/MacOS/notifier" "Alpha single" "One notification"
    for i in 1 2 3; do "$NOTIFY/Lab Bravo.app/Contents/MacOS/notifier" "Bravo $i" "Stacked $i"; done
    "$NOTIFY/Lab Charlie.app/Contents/MacOS/notifier" "Charlie buttons" "Has actions" --actions
    sleep 3
}

# The real panel, with a backdrop under Notification Center's window (level 21).
real() {
    local look=$1
    post
    "$LAB" clock; sleep 1.3
    local r; r=$("$LAB" lab-rect)
    "$LAB" backdrop "$r" 2 20 & local bd=$!; sleep 0.8
    screencapture -x -R"$r" "$OUT/cmp-real-collapsed-$look.png"; wait "$bd"
    "$NOTIFY/watch" --expand Bravo; sleep 1.2
    r=$("$LAB" lab-rect)
    "$LAB" backdrop "$r" 2 20 & bd=$!; sleep 0.8
    screencapture -x -R"$r" "$OUT/cmp-real-expanded-$look.png"; wait "$bd"
    "$LAB" shut >/dev/null
}

# Ours, through app.sh, which captures over a backdrop just under our panel.
ours() {
    local look=$1
    post
    # Without the user's banner colour, to compare with the system's own look; app.sh
    # puts it back.
    NN_SET="hasBannerColor=NO" scripts/panel-lab/app.sh open wait:1.5 "sshot:cmp-ours-collapsed-$look" click:"Bravo 3" wait:1.3 \
        "sshot:cmp-ours-expanded-$look" shut | grep -E 'png|failed|settings' || true
}

for look in dark light; do
    "$THEME" theme "$look"; sleep 2.5
    real "$look"
    ours "$look"
done

python3 - <<'PY'
from PIL import Image, ImageDraw
out = "build/panel-lab"
sheets = []
for look in ["dark", "light"]:
    cells = []
    for state in ["collapsed", "expanded"]:
        a = Image.open(f"{out}/cmp-real-{state}-{look}.png").convert("RGB")
        b = Image.open(f"{out}/cmp-ours-{state}-{look}.png").convert("RGB")
        cells.append((a, b))
    w = sum(a.width + b.width + 30 for a, b in cells)
    h = max(max(a.height, b.height) for a, b in cells) + 26
    sheet = Image.new("RGB", (w, h), (40, 40, 44))
    d = ImageDraw.Draw(sheet)
    x = 0
    for (a, b), state in zip(cells, ["collapsed", "expanded"]):
        d.text((x + 4, 6), f"{look} {state}: macOS", fill=(230, 230, 230))
        d.text((x + a.width + 10, 6), "NotificationNanny", fill=(232, 131, 58))
        sheet.paste(a, (x, 26)); sheet.paste(b, (x + a.width + 6, 26))
        x += a.width + b.width + 30
    sheet.save(f"{out}/compare-{look}.png")
    sheets.append(sheet)
total = Image.new("RGB", (max(s.width for s in sheets), sum(s.height for s in sheets) + 10), (255, 0, 255))
y = 0
for s in sheets:
    total.paste(s, (0, y)); y += s.height + 10
total.save(f"{out}/compare.png")
print("wrote build/panel-lab/compare.png")
PY
