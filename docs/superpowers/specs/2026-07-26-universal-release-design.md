# Universal release artifact design

## Problem

The v7.6.1 release archive contains an arm64-only executable. Homebrew installs
that archive unchanged, so Intel Macs install the application but macOS refuses
to launch it as unsupported.

## Scope

Change the GitHub release workflow only. The workflow will request a universal
build from `build-app.sh`, then verify the assembled app executable contains
both `arm64` and `x86_64` before packaging and uploading the ZIP.

## Design

The Build step will run `UNIVERSAL=1 ./build-app.sh`. This uses the build
script's existing, documented multi-architecture path and avoids changing the
default local build behavior.

A following Verify architecture step will inspect
`build/NotificationNanny.app/Contents/MacOS/NotificationNanny` with
`lipo -archs`. It will fail the release if either required architecture is
missing. The verification runs before ZIP creation, so an invalid release is
never uploaded or written into the Homebrew Cask.

## Non-goals

- Do not alter the app's macOS deployment target or the Cask's Sonoma minimum.
- Do not split releases or add CPU-specific Casks.
- Do not change local developer builds unless they explicitly set
  `UNIVERSAL=1`.

## Validation

The regression check is the new architecture-verification workflow step. It
must fail against the existing arm64-only v7.6.1 artifact and pass once the
release build enables the universal path. Existing Swift tests remain part of
the normal CI suite.
