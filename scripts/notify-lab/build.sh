#!/usr/bin/env bash
# Builds the notify-lab sender apps into build/notify-lab.
#
# One binary, wrapped as three bundles with their own names and bundle IDs, so
# macOS treats them as three apps. That is the only way to get several banners
# on screen at once: one app's notifications replace each other.
#
# The first notification from each app asks for permission. Allow all three
# once (System Settings > Notifications lists them as Lab Alpha/Bravo/Charlie).
set -euo pipefail
cd "$(dirname "$0")/../.."

LAB=scripts/notify-lab
OUT=build/notify-lab
mkdir -p "$OUT"

# The 27.0 SDK in the Command Line Tools needs a SwiftUI macro plugin they don't
# ship; nothing here uses SwiftUI, but pin the SDK that is known to work.
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d "$SDK" ]] && export SDKROOT="$SDK"

swiftc -O -o "$OUT/notifier" "$LAB/notifier.swift"
swiftc -O -o "$OUT/watch" "$LAB/watch.swift"

for name in Alpha Bravo Charlie; do
    lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    app="$OUT/Lab $name.app"
    mkdir -p "$app/Contents/MacOS"
    cp "$OUT/notifier" "$app/Contents/MacOS/notifier"
    cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.notificationnanny.lab.$lower</string>
    <key>CFBundleName</key><string>Lab $name</string>
    <key>CFBundleDisplayName</key><string>Lab $name</string>
    <key>CFBundleExecutable</key><string>notifier</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
    codesign --force --sign - "$app" >/dev/null
    echo "built $app"
done
