# Settings screenshot comparisons

Pull requests targeting `main` run a separate **Settings visual review** workflow.
Download its `settings-visual-review` artifact and open `report/index.html`.
It shows the base revision, proposed revision and amplified pixel differences.
`results.json` contains the measurements. Differences are advisory during the pilot;
render, build and comparison errors still fail the job.

The workflow renders both revisions on the same `macos-26` runner using the same
Xcode selection, display, installed icons and capture harness. This avoids keeping
OS-dependent reference images in git. The exact OS and toolchain versions are saved
in `environment.txt`. The base capture uses the proposed revision's snapshot test and test launcher,
with app Sources and Resources from the base revision. If a view's API changes,
keep the harness compatible with both revisions for that PR, or adapt this workflow
explicitly. No baseline is silently accepted or updated.

## Captures

Nine Settings content views, each in Light and Dark, at three configurations:

- Standard pane: 509 × 640 points, active controls.
- Standard pane with inactive controls.
- Minimum window pane: 469 × 412 points, active controls.

All images use 2× resolution, demo settings and an English locale. Preferences and
caches are isolated in a temporary home. Cleanup skips mounted filesystems, such as
Xcode's Metal toolchain, and reports busy files without changing the test result. Diagnostics stays collapsed so its live log
timestamps are excluded. The existing website capture mode remains unchanged.

These are content-pane snapshots. They do not cover the sidebar, window chrome,
content below the initial scroll position, translations, animations in motion, or
notification actions. Display information, permission status, startup state and
system app icons can still differ between machines. Compare captures made on the
same machine and toolchain. Start with review artifacts until repeated runs establish
stability; do not treat these captures as full E2E coverage.

## Local use

Full Xcode is required; Command Line Tools alone may lack SwiftUI macro plugins.
Select Xcode with `xcode-select` before running. Run the snapshot suite separately
from other tests because it uses shared demo logging state.

```sh
python3 -m venv build/visual-venv
build/visual-venv/bin/pip install -r scripts/visual-tests/requirements.txt
scripts/visual-tests/render.sh build/visual-before
# Make the UI change, then capture again on the same machine.
scripts/visual-tests/render.sh build/visual-after
build/visual-venv/bin/python scripts/visual-tests/compare.py \
  build/visual-before build/visual-after build/visual-report
open build/visual-report/index.html
```

Use fresh capture directories. The renderer rejects non-empty PNG directories to
prevent stale captures being counted as successful output. The comparator replaces
its output directory; keep it separate from either input directory.

The comparator ignores channel differences of 8/255 or less, then reports every
pixel exceeding that tolerance, without a whole-image percentage allowance that
could hide small missing controls. Use `--tolerance N` to adjust this, or
`--fail-on-change` for an optional local strict check. Added, missing and resized
captures also count as changes. An empty capture set is an error.

```sh
build/visual-venv/bin/python -m unittest discover -s scripts/visual-tests -p 'test_*.py' -v
```

For custom banners and Notification Center, continue using `scripts/banner-lab`
and `scripts/panel-lab/compare.sh` on a permitted desktop as release checks.
