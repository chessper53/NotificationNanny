#!/usr/bin/env bash
# Kill, debug-build, reset Accessibility TCC, and relaunch NotificationNanny.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="NotificationNanny"
BUNDLE_ID="com.notificationnanny.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo dev)}"
APP_DIR="build/${APP_NAME}.app"

echo "==> Killing existing instance..."
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.3

echo "==> Building (debug)..."
swift build

BINARY_PATH="$(swift build --show-bin-path)/${APP_NAME}"

# Shared with build-app.sh so a dev bundle and a release bundle differ only in
# how the binary was compiled — never in what ends up inside the .app.
echo "==> Assembling + signing .app bundle..."
scripts/assemble-bundle.sh "${BINARY_PATH}" "${APP_DIR}" "${VERSION}"

echo "==> Resetting Accessibility permission..."
tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true

echo "==> Launching..."
open "${APP_DIR}"
