#!/usr/bin/env bash
# Compare the app's actual banner view with native captures. Commands and prerequisites are in
# docs/LABS.md.
set -euo pipefail
cd "$(dirname "$0")/../.."

LAB=scripts/banner-lab
OUT=build/banner-lab
BACKDROPS=(black white gray red blue stripes checker wallpaper)
mkdir -p "$OUT/src"

echo "==> Building lab"
python3 "$LAB/expand_state.py" Sources/NotificationNannyCore/UI/Overlay/CustomOverlay.swift "$OUT/src/CustomOverlay.swift"
cp "$LAB/lab.swift" "$OUT/src/main.swift"
CORE=Sources/NotificationNannyCore
swiftc -O -D PROD -package-name NotificationNanny -o "$OUT/lab" "$OUT/src/main.swift" "$OUT/src/CustomOverlay.swift" \
    "$CORE/UI/ActiveHover.swift" "$CORE/System/LocalizationManager.swift" "$CORE/UI/NannyColors.swift"

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
