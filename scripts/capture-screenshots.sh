#!/usr/bin/env bash
# Renders every settings tab, in dark and in light, for the landing page:
# site/assets/screenshots/<tab>.webp and <tab>-light.webp, at 2x, without the
# sidebar (the site draws its own tab list beside them).
#
# The drawing happens in an opt-in snapshot test,
# Tests/NotificationNannyTests/SettingsSnapshotTests.swift, which renders each
# tab's content view offscreen with demo data. It never launches, quits, or
# reads the settings of an installed NotificationNanny, never draws on screen,
# and needs no Automation or Screen Recording permission. CFFIXED_USER_HOME
# below keeps anything the render touches inside build/ instead of ~/Library.
#
# Usage: ./scripts/capture-screenshots.sh [extra scripts/test.sh args]
#
# On a Mac with only the Command Line Tools, pass what the test suite needs there:
#   SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
#     ./scripts/capture-screenshots.sh -Xswiftc -plugin-path \
#     -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v cwebp > /dev/null; then
    echo "error: cwebp not found. Install it with: brew install webp" >&2
    exit 1
fi

OUT_DIR="build/snapshots"
SITE_DIR="site/assets/screenshots"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$SITE_DIR" build/snapshot-home

echo "==> Rendering settings tabs..."
NN_SNAPSHOT_DIR="$PWD/$OUT_DIR" CFFIXED_USER_HOME="$PWD/build/snapshot-home" \
    ./scripts/test.sh --filter SettingsSnapshotTests "$@"

shopt -s nullglob
pngs=("$OUT_DIR"/*.png)
if [[ ${#pngs[@]} -eq 0 ]]; then
    echo "error: the snapshot test wrote nothing to $OUT_DIR" >&2
    exit 1
fi

# Lossless: flat UI compresses smaller this way than at any lossy quality that
# keeps small text sharp, and nothing gets the soft edges lossy WebP adds to it.
echo "==> Converting to WebP..."
for png in "${pngs[@]}"; do
    cwebp -quiet -lossless -z 9 "$png" -o "$SITE_DIR/$(basename "$png" .png).webp"
done

echo "==> Done: ${#pngs[@]} screenshots in $SITE_DIR/. Review them, then commit."
