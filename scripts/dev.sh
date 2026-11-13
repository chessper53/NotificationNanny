#!/usr/bin/env bash
# Build and relaunch with a stable development signing identity to preserve macOS permissions.
set -euo pipefail

cd "$(dirname "$0")/.."

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

echo "==> Assembling + signing .app bundle..."
DEV_SIGNING=1 scripts/assemble-bundle.sh "${BINARY_PATH}" "${APP_DIR}" "${VERSION}"


echo "==> Launching..."
open "${APP_DIR}"
