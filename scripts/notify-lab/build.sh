#!/usr/bin/env bash
# Build three distinct Lab app bundles so simultaneous notifications can come from separate apps.
# Allow their notifications once; setup and commands are in docs/LABS.md.
set -euo pipefail
cd "$(dirname "$0")/../.."

LAB=scripts/notify-lab
OUT=build/notify-lab
mkdir -p "$OUT"

# Use the older SDK to avoid the current Command Line Tools' missing SwiftUI macro plugin.
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
