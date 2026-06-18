# Contributing

Thanks for your interest in NotificationNanny! This is a small, single-maintainer
project, so contributions are welcome but please keep PRs focused and discuss
larger changes in an issue first.

## Getting set up

- macOS 14+ and either **full Xcode** or the **Command Line Tools**.
- No third-party dependencies — it's pure Swift Package Manager.

```sh
git clone https://github.com/chessper53/NotificationNanny
cd NotificationNanny
make build        # or: swift build
./dev.sh          # kill, build, reset permission, launch
```

See [DEBUGGING.md](DEBUGGING.md) for the full build/run/debug loop and why
code-signing + Accessibility permission matter.

## Project layout

All logic lives in the `NotificationNannyCore` library target (so it's testable);
the executable target is a thin entry point. For the full picture — module
structure, the AX engine, the banner-rendering decision tree, and the key design
patterns — read [ARCHITECTURE.md](ARCHITECTURE.md).

## Tests

```sh
make test     # handles the CLT-only Testing.framework wiring
# or, with full Xcode:
swift test
```

Add tests for domain logic (geometry, placement, settings, groups, presets) in
`Tests/NotificationNannyTests/`. The AX observation loop, custom-banner windows,
and private SPI are validated manually (they need a live system).

## Coding conventions

- Match the surrounding code: `@MainActor` throughout, Combine `@Published` for
  settings, the `NotificationSettingsProviding` protocol for repositioner inputs.
- Keep private SPI declarations in `PrivateWindowAPI.swift` — don't scatter
  `@_silgen_name` across business logic.
- New settings: add the key, the `@Published` property with a persisting `didSet`,
  protocol conformance if the repositioner reads it, and an entry in the export
  schema (use an `Optional` field so old backups still decode).

## Before opening a PR

1. `make test` passes.
2. `./dev.sh` runs and the change behaves as intended against real notifications.
3. Update [CHANGELOG.md](CHANGELOG.md) and, for structural changes,
   [ARCHITECTURE.md](ARCHITECTURE.md).
4. Keep the diff scoped to one change; describe how you verified it.

## Reporting bugs

Use **Help → Report a bug** in the app — it pre-fills diagnostics and recent logs.
Otherwise, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) first, then
[open an issue](https://github.com/chessper53/NotificationNanny/issues) with your
macOS version and steps to reproduce.

## Releases

Maintainer-only; see [RELEASING.md](RELEASING.md).
