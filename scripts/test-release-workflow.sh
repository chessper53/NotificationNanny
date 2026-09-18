#!/usr/bin/env bash
# Guards the release workflow's contract.
#
# It used to assert that the workflow built its own universal binary. It no
# longer builds anything: release.sh is the only builder, and the workflow's job
# is to check what that actually published. So the contract being guarded here
# changed from "CI builds universal" to "CI proves the published zip is
# universal, signed, correctly stamped, and matched by the cask".
set -euo pipefail

workflow="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/release.yml"

require() {
  grep -qF "$2" "$workflow" || {
    echo "release workflow must $1 (missing: $2)" >&2
    exit 1
  }
}

require "inspect the artifact that was actually published, not a fresh build" \
  'gh release download'
require "verify the published binary's architectures" \
  'lipo -archs'
require "reject a published binary that is not universal" \
  'for architecture in arm64 x86_64'
require "verify the published app is validly signed" \
  'codesign --verify --strict'
require "verify the cask's sha256 matches the published zip" \
  'expected_sha'

# The old failure mode: a second builder whose upload always collided with the
# zip release.sh had already attached, turning every release red and leaving the
# real artifact unchecked. Uploading from CI also breaks the cask's sha256,
# which release.sh computes from its own local zip.
if grep -qE '^\s*run:.*gh release upload' "$workflow"; then
  echo "release workflow must not upload artifacts: release.sh owns the zip, and replacing it invalidates the cask's sha256" >&2
  exit 1
fi
