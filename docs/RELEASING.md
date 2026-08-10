# Releasing NotificationNanny

Releases are **intentional and manual** — there is no automatic release on version
bumps. One script does the whole job: build, package, publish the GitHub release,
update the Homebrew cask, and push.

## TL;DR

```sh
# 1. Bump the version (single source of truth)
echo "7.6.0" > VERSION
git commit -am "chore: bump version to 7.6.0"

# 2. Cut the release (builds, zips, publishes, bumps cask, pushes)
./release.sh 7.6.0
```

Users then upgrade with:

```sh
brew update && brew upgrade --cask notificationnanny
```

## What `release.sh <version>` does

1. Builds a release `.app` with the version stamped into `Info.plist` (`build-app.sh`).
2. Packages it into `NotificationNanny-<version>.zip` with `ditto` (preserves
   code-signing xattrs).
3. Computes the `sha256`.
4. Creates the GitHub release `v<version>` and uploads the zip (`gh release create … --latest`).
5. Rewrites `version` and `sha256` in [`Casks/notificationnanny.rb`](../Casks/notificationnanny.rb).
6. Commits the cask bump (`cask: bump to v<version>`) and pushes.

### Preconditions (the script enforces these)

- `gh` CLI installed and authenticated (`gh auth status`).
- Clean working tree — commit or stash first.
- Tag `v<version>` must not already exist locally.

## Screenshots

`README.md` and `site/index.html` both reference the same six settings-tab
screenshots (Position, Banner, Exceptions, Presets, General, Help) by filename
from `docs/screenshots/` and `site/assets/screenshots/` — not an external URL.
To refresh them for a release:

```sh
./scripts/capture-screenshots.sh --launch
```

It builds and launches the app, clicks through each tab via System Events, and
writes matching PNGs into both directories. Run it, look over the results, then
`git add docs/screenshots site/assets/screenshots` alongside your other release
changes — there's no manual capture-and-reupload step.

One-time setup: the terminal running the script needs Automation permission to
drive the app's UI (System Settings → Privacy & Security → Automation → your
terminal → System Events). macOS prompts for this the first time you run it
interactively; if it fails with "Not authorized to send Apple events to System
Events," that permission hasn't been granted yet.

## Versioning

- [`VERSION`](../VERSION) is the single source of truth; `build-app.sh` reads it.
- Follow [SemVer](https://semver.org): breaking/large UX change → major, new
  feature → minor, fix-only → patch.
- Add a matching section to [CHANGELOG.md](CHANGELOG.md) **before** releasing.

## Build architecture

`build-app.sh` defaults to the **host architecture only** (currently `arm64`) so it
works with just the Command Line Tools. Historical releases (≤ 7.5.0) shipped
arm64-only.

To ship a **universal** (arm64 + x86_64) binary for Intel Macs you need **full
Xcode** installed, then:

```sh
UNIVERSAL=1 ./release.sh 7.6.0
```

## A note on the `release.yml` workflow

[`.github/workflows/release.yml`](../.github/workflows/release.yml) triggers on
*release published* and tries to build + upload + bump the cask in CI. Because
`release.sh` already does all of that locally, that CI run is **redundant** and
will **fail on the duplicate zip upload** — this is harmless and expected. If you
prefer a clean Actions tab, you can either delete `release.yml` (rely solely on
`release.sh`) or make its upload step use `--clobber`.

> The old `auto-release.yml` (which published a release on every `VERSION` change)
> was removed deliberately — it fired releases unintentionally on doc commits.

## Manual fallback

If `release.sh` fails partway, the equivalent steps are:

```sh
VERSION=7.6.0 bash build-app.sh
ditto -c -k --sequesterRsrc --keepParent build/NotificationNanny.app build/NotificationNanny-7.6.0.zip
shasum -a 256 build/NotificationNanny-7.6.0.zip          # note the hash

gh release create v7.6.0 build/NotificationNanny-7.6.0.zip --title "NotificationNanny 7.6.0" --generate-notes --latest
# (or, if the release already exists:)
gh release upload v7.6.0 build/NotificationNanny-7.6.0.zip --clobber

# Update version + sha256 in Casks/notificationnanny.rb, then:
git commit -am "cask: bump to v7.6.0" && git push
```

## Verify a release

```sh
# The cask sha256 must match the published asset, or brew install fails.
curl -sL -o /tmp/nn.zip "https://github.com/chessper53/NotificationNanny/releases/download/v7.6.0/NotificationNanny-7.6.0.zip"
shasum -a 256 /tmp/nn.zip
grep sha256 Casks/notificationnanny.rb
```
