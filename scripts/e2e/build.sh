#!/usr/bin/env bash
# Build only; never launches apps, resets permissions, or installs anything.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# -gt 1 || ($# == 1 && $1 != --helpers-only) ]]; then
    echo "usage: bash scripts/e2e/build.sh [--helpers-only]" >&2
    exit 64
fi
# The current CLT's SwiftUI macros need the older SDK, as in the existing labs.
if [[ -z "${SDKROOT:-}" && $(xcode-select -p) == *CommandLineTools* && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
export CLANG_MODULE_CACHE_PATH="$PWD/build/e2e/module-cache"
mkdir -p build/e2e
bash scripts/notify-lab/build.sh
swiftc -O -swift-version 5 scripts/e2e/probe.swift -o build/e2e/probe
if [[ ${1:-} != --helpers-only ]]; then
    swift build
    bash scripts/assemble-bundle.sh "$(swift build --show-bin-path)/NotificationNanny" build/NotificationNanny.app "$(tr -d '[:space:]' < VERSION)"
fi
