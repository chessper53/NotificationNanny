#!/usr/bin/env bash
# Render Settings tabs with demo data, off screen and without accessing installed app preferences.
# See docs/DEBUGGING.md for commands and toolchain setup.

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

# Lossless WebP preserves small text and compresses flat UI efficiently.
echo "==> Converting to WebP..."
for png in "${pngs[@]}"; do
    cwebp -quiet -lossless -z 9 "$png" -o "$SITE_DIR/$(basename "$png" .png).webp"
done

echo "==> Done: ${#pngs[@]} screenshots in $SITE_DIR/. Review them, then commit."
