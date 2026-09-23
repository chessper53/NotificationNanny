#!/usr/bin/env bash
# Measures the custom banner against the real Notification Center banner.
#
#   scripts/banner-lab/run.sh            capture real + ours in the current
#                                        appearance, then score
#   scripts/banner-lab/run.sh --light    the same in Light Mode (switches the
#                                        system appearance and restores it)
#   scripts/banner-lab/run.sh --both     both appearances
#
# Output lands in build/banner-lab: captures under cap/<appearance>/, and a
# side by side sheet-<appearance>-ours.png per run. Lower scores are closer; see score.py.
# For a quick look at a parameter change without touching the app, the lab's
# `cand` mode renders an AppKit mock-up instead (see lab.swift).
#
# The app's CustomOverlay.swift is compiled straight into the lab, so what is
# measured is the real view. The Command Line Tools ship no SwiftUI macro
# plugin, so expand_state.py first rewrites its @State properties into the
# State<T> storage the macro would have produced.
#
# Needs Accessibility and Screen Recording for the app running this, and
# Pillow + NumPy for scoring. Keep NotificationNanny's banner animation on
# Default while it runs, or quit it, so the real banner stays the real one.
set -euo pipefail
cd "$(dirname "$0")/../.."

LAB=scripts/banner-lab
OUT=build/banner-lab
BACKDROPS=(black white gray red blue stripes checker wallpaper)
mkdir -p "$OUT/src"

echo "==> Building lab"
python3 "$LAB/expand_state.py" Sources/NotificationNannyCore/UI/Overlay/CustomOverlay.swift "$OUT/src/CustomOverlay.swift"
cp "$LAB/lab.swift" "$OUT/src/main.swift"
swiftc -O -D PROD -package-name NotificationNanny -o "$OUT/lab" "$OUT/src/main.swift" "$OUT/src/CustomOverlay.swift"

measure() {
    local appearance=$1
    echo "==> Real banner ($appearance)"
    "$OUT/lab" real "${BACKDROPS[@]}"
    echo "==> Ours ($appearance)"
    "$OUT/lab" prod ours -- "${BACKDROPS[@]}"
    python3 "$LAB/score.py" --appearance "$appearance" -v --sheet ours
}

current=$(defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark && echo dark || echo light)
restore() { "$OUT/lab" theme "$current"; }

case "${1:-}" in
    --light|--both)
        trap restore EXIT
        [[ "${1}" == --both ]] && { "$OUT/lab" theme dark; sleep 2; measure dark; }
        "$OUT/lab" theme light; sleep 2; measure light
        ;;
    *)
        measure "$current"
        ;;
esac
