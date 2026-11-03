#!/usr/bin/env bash
# Screenshots for lab runs from a terminal without Screen Recording (an editor's).
#
#   scripts/panel-lab/shot.sh screencapture <args…>
#   scripts/panel-lab/shot.sh window <windowID> <out.png>
#
# The first run builds build/panel-lab/Shot.app and macOS asks to allow it Screen
# Recording; allow it once. It is never rebuilt, so the grant stays (delete the app to
# build it again, and allow it again).
set -euo pipefail
cd "$(dirname "$0")/../.."
APP=build/panel-lab/Shot.app
if [[ ! -x "$APP/Contents/MacOS/Shot" ]]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
    [[ -d "$SDK" ]] && export SDKROOT="$SDK"
    mkdir -p "$APP/Contents/MacOS"
    swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/Shot" scripts/panel-lab/shot.swift
    cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.notificationnanny.panel-lab.shot</string>
    <key>CFBundleName</key><string>NotificationNanny Lab Shot</string>
    <key>CFBundleExecutable</key><string>Shot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
    codesign --force --sign - "$APP" >/dev/null 2>&1
fi
# Relative paths are the repo's; the app runs elsewhere.
args=()
for a in "$@"; do [[ "$a" == *.png && "$a" != /* ]] && a="$PWD/$a"; args+=("$a"); done
out="${args[${#args[@]}-1]}"
txt="$PWD/build/panel-lab/shot.txt"; [[ "$out" == *.png ]] && txt="$out.txt"
rm -f "$txt"
open -W -n -a "$PWD/$APP" --args "${args[@]}"
cat "$txt" 2>/dev/null || echo "no report"
