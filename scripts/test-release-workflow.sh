#!/usr/bin/env bash
set -euo pipefail

workflow="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/release.yml"

grep -qF 'run: UNIVERSAL=1 ./build-app.sh' "$workflow" || {
  echo "release workflow must request a universal build" >&2
  exit 1
}
grep -qF 'lipo -archs' "$workflow" || {
  echo "release workflow must verify its binary architectures" >&2
  exit 1
}
