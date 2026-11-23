#!/usr/bin/env bash
# Add Testing framework and runtime paths for Command Line Tools installations.
# Forward arguments to swift test; full Xcode needs no extra paths.
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

# Bash 3 treats an empty array as unset when nounset is enabled.
if [[ ${#ARGS[@]} -gt 0 ]]; then
    exec swift test "${ARGS[@]}" "$@"
fi
exec swift test "$@"
