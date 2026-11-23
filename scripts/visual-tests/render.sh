#!/usr/bin/env bash
# Run separately from other suites. Accepts an output directory and Swift test flags.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT_DIR=${1:?Usage: render.sh OUTPUT_DIRECTORY [swift test arguments]}
shift
mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)
if compgen -G "$OUT_DIR/*.png" > /dev/null; then
    echo "error: use a fresh output directory (PNG captures already exist)" >&2
    exit 1
fi
# Isolate preferences, localization and caches from the desktop user.
SNAPSHOT_HOME=$(mktemp -d "${TMPDIR:-/tmp}/nn-visual-home.XXXXXX")
trap 'rm -rf "$SNAPSHOT_HOME"' EXIT
NN_VISUAL_REVIEW=1 NN_SNAPSHOT_DIR="$OUT_DIR" CFFIXED_USER_HOME="$SNAPSHOT_HOME" \
    scripts/test.sh --filter SettingsSnapshotTests "$@"
python3 - "$OUT_DIR" <<'PY'
from pathlib import Path
import sys
files = list(Path(sys.argv[1]).glob('*.png'))
if len(files) != 54:
    raise SystemExit(f'Expected 54 Settings captures, found {len(files)}')
PY
