#!/usr/bin/env bash
# What the release workflow must keep doing; a static check of release.yml.
set -euo pipefail

workflow="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/release.yml"

need() {
  grep -qF -- "$1" "$workflow" || { echo "release workflow must $2" >&2; exit 1; }
}

need 'run: UNIVERSAL=1 ./scripts/build-app.sh' "request a universal build"
need 'lipo -archs' "verify its binary architectures"
need 'secrets.SIGNING_P12' "sign with the release certificate"
need 'certificate leaf' "check the signature is the certificate's"
need 'ditto -c -k' "package with ditto, which keeps the signature intact"
need 'ditto -x -k' "check the archive itself, unpacked"
need '--draft' "upload to a draft before publishing"
need 'gh release download' "check the uploaded archive before publishing"
need 'checkout -q -B cask-update origin/main' "update the cask on main as it is now"
if grep -qE '^\s*release:\s*$' "$workflow" && grep -qF 'types: [published]' "$workflow"; then
  echo "release workflow must not run on a published release: it publishes the release itself" >&2
  exit 1
fi
echo "release workflow checks pass"
