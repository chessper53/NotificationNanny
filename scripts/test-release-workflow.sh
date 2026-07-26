#!/usr/bin/env bash
set -euo pipefail

workflow="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/release.yml"

rg -F 'run: UNIVERSAL=1 ./build-app.sh' "$workflow" >/dev/null || {
  echo "release workflow must request a universal build" >&2
  exit 1
}
rg -F 'lipo -archs' "$workflow" >/dev/null || {
  echo "release workflow must verify its binary architectures" >&2
  exit 1
}
