#!/usr/bin/env bash
# Validate main and VERSION, then tag and push for the release workflow.
# The workflow alone builds and publishes; see docs/RELEASING.md.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: ./scripts/release.sh <version>  e.g.  ./scripts/release.sh 8.1.0}"
TAG="v${VERSION}"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: uncommitted changes. Commit or stash them first." >&2
    exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "error: release from main." >&2
    exit 1
fi

git fetch -q origin main --tags
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    echo "error: main isn't the same as origin/main. Pull or push first." >&2
    exit 1
fi

if [[ "$(tr -d '[:space:]' < VERSION)" != "$VERSION" ]]; then
    echo "error: VERSION says $(tr -d '[:space:]' < VERSION). Bump it to $VERSION in a commit on main first." >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    echo "error: tag ${TAG} already exists. To build it again: gh workflow run release.yml -f tag=${TAG}" >&2
    exit 1
fi

git tag -a "${TAG}" -m "NotificationNanny ${VERSION}"
git push -q origin "${TAG}"

echo "Tagged and pushed ${TAG}. The release workflow builds, checks and publishes it."
echo "Follow it with:  gh run watch \$(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
