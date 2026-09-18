#!/usr/bin/env bash
# Build NotificationNanny.app from the SwiftPM sources — no Xcode required.
#
# Output: ./build/NotificationNanny.app
#
# Usage:
#   ./build-app.sh           # build only
#   ./build-app.sh --run     # build, then open the app
#   ./build-app.sh --install # build, then copy to /Applications

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="NotificationNanny"
BUNDLE_ID="com.notificationnanny.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo dev)}"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

# A universal build (--arch arm64 --arch x86_64) needs full Xcode. Default to the
# host arch so this works with just the Command Line Tools. Set UNIVERSAL=1 to
# opt in if you have full Xcode.
SWIFT_BUILD_ARGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling (release)…"
swift build "${SWIFT_BUILD_ARGS[@]}"

BINARY_PATH="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)/${APP_NAME}"

# Shared with dev.sh so a dev bundle and a release bundle differ only in how the
# binary was compiled — never in what ends up inside the .app.
echo "==> Assembling + ad-hoc signing .app bundle…"
scripts/assemble-bundle.sh "${BINARY_PATH}" "${APP_DIR}" "${VERSION}"

echo "==> Built ${APP_DIR}"

case "${1:-}" in
    --run)
        echo "==> Killing existing instance…"
        pkill -x "${APP_NAME}" 2>/dev/null || true
        sleep 0.3
        echo "==> Resetting Accessibility permission…"
        tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true
        echo "==> Launching…"
        open "${APP_DIR}"
        ;;
    --install)
        echo "==> Installing to /Applications…"
        rm -rf "/Applications/${APP_NAME}.app"
        cp -R "${APP_DIR}" "/Applications/"
        echo "==> Installed. Launch it from /Applications."
        ;;
esac
