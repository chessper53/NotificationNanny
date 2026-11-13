#!/usr/bin/env bash
# Build a release app bundle with full Xcode. Commands are in docs/DEBUGGING.md.
# The current Command Line Tools lack the required SwiftUI macro plugin.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="NotificationNanny"
BUNDLE_ID="com.notificationnanny.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo dev)}"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

# UNIVERSAL=1 includes Intel support; otherwise build for the host architecture.
SWIFT_BUILD_ARGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling (release)…"
swift build "${SWIFT_BUILD_ARGS[@]}"

BINARY_PATH="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)/${APP_NAME}"

echo "==> Assembling + signing .app bundle…"
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
