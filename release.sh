#!/usr/bin/env bash
# Create a NotificationNanny release.
#
# Usage: ./release.sh <version>   e.g.  ./release.sh 3.0.0
#
# What it does:
#   1. Builds a release .app with the given version stamped in Info.plist
#   2. Packages it into a ZIP (using ditto, which preserves code-signing xattrs)
#   3. Computes sha256
#   4. Creates a GitHub release + uploads the ZIP
#   5. Updates Casks/notificationnanny.rb with the new version + sha256
#   6. Commits and pushes so the Homebrew tap picks up the change immediately

set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh <version>  e.g.  ./release.sh 3.0.0}"
TAG="v${VERSION}"
ZIP_NAME="NotificationNanny-${VERSION}.zip"
CASK_FILE="Casks/notificationnanny.rb"

# Guard: require gh CLI
if ! command -v gh &>/dev/null; then
    echo "error: 'gh' CLI not found. Install with: brew install gh" >&2
    exit 1
fi

# Guard: no uncommitted changes (cask commit needs a clean tree)
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: uncommitted changes in working tree. Commit or stash them first." >&2
    exit 1
fi

# Guard: tag must not already exist
if git rev-parse "${TAG}" &>/dev/null; then
    echo "error: tag ${TAG} already exists locally. Delete it first if you're re-releasing." >&2
    exit 1
fi

echo "==> Building ${VERSION}…"
VERSION="${VERSION}" bash build-app.sh

echo "==> Packaging ${ZIP_NAME}…"
rm -f "build/${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "build/NotificationNanny.app" "build/${ZIP_NAME}"

SHA=$(shasum -a 256 "build/${ZIP_NAME}" | awk '{print $1}')
echo "    sha256: ${SHA}"

echo "==> Publishing GitHub release ${TAG}…"
gh release create "${TAG}" "build/${ZIP_NAME}" \
    --title "NotificationNanny ${VERSION}" \
    --generate-notes \
    --latest

echo "==> Updating ${CASK_FILE}…"
sed -i '' \
    -e "s/version \"[^\"]*\"/version \"${VERSION}\"/" \
    -e "s/sha256 \"[^\"]*\"/sha256 \"${SHA}\"/" \
    "${CASK_FILE}"

git add "${CASK_FILE}"
git commit -m "cask: bump to ${TAG}"
git push

echo ""
echo "Done! NotificationNanny ${VERSION} is live."
echo "Users upgrade with:  brew update && brew upgrade --cask notificationnanny"
