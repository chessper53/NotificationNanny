#!/usr/bin/env bash
# Assemble the same bundle resources for development and release builds. See docs/RELEASING.md.

set -euo pipefail

BINARY_PATH="${1:?usage: assemble-bundle.sh <binary-path> <app-dir> <version>}"
APP_DIR="${2:?usage: assemble-bundle.sh <binary-path> <app-dir> <version>}"
VERSION="${3:?usage: assemble-bundle.sh <binary-path> <app-dir> <version>}"

APP_NAME="NotificationNanny"
BUNDLE_ID="com.notificationnanny.app"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

if [[ ! -f "${BINARY_PATH}" ]]; then
    echo "error: built binary not found at ${BINARY_PATH}" >&2
    exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

sed \
    -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
    -e "s/\$(MARKETING_VERSION)/${VERSION}/g" \
    "${ROOT}/Resources/Info.plist" > "${CONTENTS}/Info.plist"

if [[ -f "${ROOT}/Resources/AppIcon.icns" ]]; then
    cp "${ROOT}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Preserve the Glyphs subdirectory for Bundle.main lookups.
if [[ -d "${ROOT}/Resources/Glyphs" ]]; then
    cp -R "${ROOT}/Resources/Glyphs" "${RESOURCES_DIR}/"
fi

# Copy plain localization folders so Bundle.main resolves them without an Xcode resource compiler.
for lproj in "${ROOT}"/Resources/*.lproj; do
    [[ -d "${lproj}" ]] || continue
    cp -R "${lproj}" "${RESOURCES_DIR}/"
done

# Stable signing identities preserve macOS permissions across builds.
# SIGN_IDENTITY and SIGN_KEYCHAIN select release signing; DEV_SIGNING selects the development
# identity.
# Without either, use an ad hoc signature for CI checks.
IDENTITY="${SIGN_IDENTITY:--}"
KEYCHAIN_ARGS=()
if [[ "${DEV_SIGNING:-}" == 1 ]]; then
    "${ROOT}/scripts/dev-signing.sh"
    SIGN_KEYCHAIN="${ROOT}/build/dev-signing/dev.keychain-db"
    security unlock-keychain -p notificationnanny-dev "${SIGN_KEYCHAIN}"
    IDENTITY="$(cat "${ROOT}/build/dev-signing/identity")"
fi
[[ -n "${SIGN_KEYCHAIN:-}" ]] && KEYCHAIN_ARGS=(--keychain "${SIGN_KEYCHAIN}")
codesign --force --deep --sign "${IDENTITY}" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
    --entitlements "${ROOT}/Resources/NotificationNanny.entitlements" \
    "${APP_DIR}"
