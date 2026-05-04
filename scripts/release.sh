#!/usr/bin/env bash
# Build a release zip + print the SHA256 you need for the Homebrew Cask.
#
# Usage:  ./scripts/release.sh 0.1.0

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: release.sh <version>}"

echo "==> Generating icon…"
swift scripts/generate-icon.swift > /dev/null

echo "==> Building app…"
./build-app.sh > /dev/null

OUT="build/NotificationNanny-${VERSION}.zip"
rm -f "${OUT}"

echo "==> Zipping app bundle…"
ditto -ck --keepParent --rsrc build/NotificationNanny.app "${OUT}"

SHA=$(shasum -a 256 "${OUT}" | awk '{print $1}')
SIZE=$(stat -f%z "${OUT}")

cat <<EOF

==> Release artefact ready
    File:   ${OUT}
    Size:   ${SIZE} bytes
    SHA256: ${SHA}

Next steps:
  1. Create a GitHub release tagged v${VERSION} and upload ${OUT}.
  2. Update Casks/notificationnanny.rb:
        version  "${VERSION}"
        sha256   "${SHA}"
        url      "https://github.com/<your-user>/NotificationNanny/releases/download/v${VERSION}/NotificationNanny-${VERSION}.zip"
  3. Publish the cask in a tap, e.g.
        brew tap <your-user>/notificationnanny
        brew install --cask <your-user>/notificationnanny/notificationnanny
EOF
