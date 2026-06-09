#!/usr/bin/env bash
# Kill, debug-build, reset Accessibility TCC, and relaunch NotificationNanny.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="NotificationNanny"
BUNDLE_ID="com.notificationnanny.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo dev)}"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

echo "==> Killing existing instance..."
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.3

echo "==> Building (debug)..."
swift build

BINARY_PATH="$(swift build --show-bin-path)/${APP_NAME}"

echo "==> Assembling .app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
sed \
    -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
    -e "s/\$(MARKETING_VERSION)/${VERSION}/g" \
    Resources/Info.plist > "${CONTENTS}/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "==> Codesigning..."
codesign --force --deep --sign - \
    --entitlements Resources/NotificationNanny.entitlements \
    "${APP_DIR}"

echo "==> Resetting Accessibility permission..."
tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true

echo "==> Launching..."
open "${APP_DIR}"
