#!/usr/bin/env bash
set -euo pipefail

# Guards against the exact bug that shipped in v7.6.0/7.6.1/7.7.0: Info.plist's
# LSMinimumSystemVersion silently drifting from the cask's `depends_on macos:`
# requirement. Pure text parsing (no PlistBuddy) so this runs on any runner.

root="$(cd "$(dirname "$0")/.." && pwd)"
cask="$root/Casks/notificationnanny.rb"
plist="$root/Resources/Info.plist"

macos_symbol_to_version() {
  case "$1" in
    :sonoma)  echo "14.0" ;;
    :sequoia) echo "15.0" ;;
    :tahoe)   echo "26.0" ;;
    *)        echo "" ;;
  esac
}

cask_symbol=$(grep -oE 'depends_on macos: :[a-z]+' "$cask" | awk '{print $NF}')
if [ -z "$cask_symbol" ]; then
  echo "error: could not find 'depends_on macos: :<symbol>' in $cask" >&2
  exit 1
fi

expected_version=$(macos_symbol_to_version "$cask_symbol")
if [ -z "$expected_version" ]; then
  echo "error: unrecognised macOS symbol '$cask_symbol' in cask — add it to $(basename "$0")" >&2
  exit 1
fi

plist_version=$(grep -A1 '<key>LSMinimumSystemVersion</key>' "$plist" | tail -1 \
  | sed -E 's/.*<string>([^<]*)<\/string>.*/\1/')

if [ "$plist_version" != "$expected_version" ]; then
  echo "error: Info.plist LSMinimumSystemVersion ($plist_version) does not match the cask's depends_on macos: $cask_symbol (expects $expected_version)" >&2
  exit 1
fi

echo "OK: Info.plist LSMinimumSystemVersion ($plist_version) matches cask depends_on macos: $cask_symbol"
