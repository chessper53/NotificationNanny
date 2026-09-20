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
UNIVERSAL=1 ./release.sh 7.6.0
```

`UNIVERSAL=1` is not optional for a real release. Without it you ship an
arm64-only binary that Intel Macs cannot launch at all. It needs full Xcode.
CI catches the mistake right after publishing, but it catches it, it does not
prevent it, so the flag belongs in the command you actually run.

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

`build-app.sh` defaults to the **host architecture only** (currently `arm64`).
That default is a leftover from when the build worked with just the Command Line
Tools, which stopped being true with CLT 27.0 in September 2026. Releases 7.5.0
and earlier shipped arm64-only; 7.6.0 onward are universal.

To ship a **universal** (arm64 + x86_64) binary for Intel Macs you need **full
Xcode** installed, then:

```sh
UNIVERSAL=1 ./release.sh 7.6.0
```

## `release.yml` is what actually ships the build

[`.github/workflows/release.yml`](../.github/workflows/release.yml) triggers on
*release published* and does the real work:

1. builds with `UNIVERSAL=1` on a runner with full Xcode,
2. fails the run if the binary is not both arm64 and x86_64,
3. zips it and attaches it to the release,
4. rewrites `version` and `sha256` in the cask and pushes that to `main`.

**This means you do not need a local toolchain to cut a release.** Publishing
the release is the trigger; the runner builds and uploads. That matters when the
Command Line Tools cannot build the project, which has been the case since CLT
27.0 dropped the SwiftUI macro plugin.

Every run from 7.3.1 to 7.7.0 failed, always at the final *Commit cask* step:
the `release` event checks out a detached HEAD, so a bare `git push` had nothing
to push to and the cask bump never landed. Fixed in `44e3109` by pushing
explicitly to `main`, which first takes effect in 8.0.0. Earlier releases had
their cask bumped by hand afterwards, which is why the tap still worked.

The upload uses `--clobber` so the job can be re-run after a later step fails.
That is safe **only** because this job is the sole builder: the `sha256` written
into the cask always comes from the same zip the same run attached. If a second
producer ever uploads a differently-built zip, the cask's hash stops matching
the asset and `brew install` fails its integrity check for everyone.

> `release.sh` also builds, uploads and bumps the cask locally. Running it
> *and* letting the workflow run means exactly that two-producer situation.
> In practice releases have been cut by publishing the release and letting CI
> do the work, which is the path described above.

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
