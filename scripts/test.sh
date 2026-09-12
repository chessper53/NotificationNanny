#!/usr/bin/env bash
# Runs the test suite.
#
# Plain `swift test` fails on machines with only the Command Line Tools
# installed (no Xcode.app): swift-testing ships inside CLT, but SwiftPM doesn't
# add its framework search path or the rpath for lib_TestingInterop.dylib, so
# every test file's `import Testing` fails to resolve and the bundle won't
# dlopen. CI selects a full Xcode and doesn't need any of this, which is why
# the suite is green there while `swift test` is broken locally.
#
# Usage: scripts/test.sh [extra swift test args...]
set -euo pipefail

cd "$(dirname "$0")/.."

ARGS=()
DEVROOT="$(xcode-select -p)"
if [[ "${DEVROOT}" == *"CommandLineTools"* ]]; then
    FRAMEWORKS="${DEVROOT}/Library/Developer/Frameworks"
    INTEROP="${DEVROOT}/Library/Developer/usr/lib"
    if [[ -d "${FRAMEWORKS}/Testing.framework" ]]; then
        echo "==> Command Line Tools toolchain — adding swift-testing search paths"
        ARGS+=(-Xswiftc -F -Xswiftc "${FRAMEWORKS}")
        ARGS+=(-Xlinker -rpath -Xlinker "${FRAMEWORKS}")
        ARGS+=(-Xlinker -rpath -Xlinker "${INTEROP}")
    fi
fi

exec swift test "${ARGS[@]}" "$@"
