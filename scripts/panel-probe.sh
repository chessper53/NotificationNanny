#!/usr/bin/env bash
# Build and run the native panel probe described in docs/LABS.md.
set -euo pipefail
cd "$(dirname "$0")/.."

# Pin the working older SDK to avoid missing macro plugins in the current Command Line Tools.
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d "$SDK" ]] && export SDKROOT="$SDK"

mkdir -p build/panel-probe
swiftc -O -swift-version 5 -o build/panel-probe/probe scripts/panel-probe.swift
exec build/panel-probe/probe "$@"
