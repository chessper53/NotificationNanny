#!/usr/bin/env bash
# Builds and runs scripts/panel-probe.swift; see its header for what it does.
set -euo pipefail
cd "$(dirname "$0")/.."

# The 27.0 SDK in the Command Line Tools needs a SwiftUI macro plugin they don't
# ship; nothing here uses SwiftUI, but pin the SDK that is known to work.
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d "$SDK" ]] && export SDKROOT="$SDK"

mkdir -p build/panel-probe
swiftc -O -swift-version 5 -o build/panel-probe/probe scripts/panel-probe.swift
exec build/panel-probe/probe "$@"
