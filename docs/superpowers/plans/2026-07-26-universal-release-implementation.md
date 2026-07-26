# Universal Release Artifact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each GitHub release ZIP launchable on both Apple Silicon and Intel Macs.

**Architecture:** Reuse `build-app.sh`'s existing `UNIVERSAL=1` path only in the release workflow. Add a workflow-local `lipo` assertion before the ZIP step, so release publication stops if either supported CPU architecture is absent.

**Tech Stack:** GitHub Actions YAML, Bash, SwiftPM, macOS `lipo`.

---

### Task 1: Guard the release workflow's compatibility contract

**Files:**
- Create: `scripts/test-release-workflow.sh`
- Modify: `.github/workflows/release.yml:20-25`
- Test: `scripts/test-release-workflow.sh`

- [ ] **Step 1: Write the failing workflow-contract test**

Create `scripts/test-release-workflow.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

workflow="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/release.yml"

rg -F 'run: UNIVERSAL=1 ./build-app.sh' "$workflow" >/dev/null || {
  echo "release workflow must request a universal build" >&2
  exit 1
}
rg -F 'lipo -archs' "$workflow" >/dev/null || {
  echo "release workflow must verify its binary architectures" >&2
  exit 1
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/test-release-workflow.sh`

Expected: exit status 1 and `release workflow must request a universal build`, because the current Build step runs `./build-app.sh` without `UNIVERSAL=1`.

- [ ] **Step 3: Enable universal build and verify its output before packaging**

Replace the Build step in `.github/workflows/release.yml` and insert the following step immediately before `Zip`:

```yaml
      - name: Build
        run: UNIVERSAL=1 ./build-app.sh

      - name: Verify universal binary
        run: |
          executable="build/NotificationNanny.app/Contents/MacOS/NotificationNanny"
          architectures="$(lipo -archs "$executable")"
          for architecture in arm64 x86_64; do
            if [[ " $architectures " != *" $architecture "* ]]; then
              echo "error: release binary is missing $architecture (found: $architectures)" >&2
              exit 1
            fi
          done
```

- [ ] **Step 4: Run the workflow-contract test to verify it passes**

Run: `bash scripts/test-release-workflow.sh`

Expected: exit status 0 with no output.

- [ ] **Step 5: Commit the workflow contract and implementation**

Run:

```bash
git add .github/workflows/release.yml scripts/test-release-workflow.sh
git commit -m "fix: build universal release artifacts"
```

Expected: one commit containing the release workflow and its regression test.

### Task 2: Build and inspect the universal application locally

**Files:**
- Modify: `build/NotificationNanny.app` (generated, ignored)
- Test: `build/NotificationNanny.app/Contents/MacOS/NotificationNanny`

- [ ] **Step 1: Create a release-equivalent app bundle**

Run: `UNIVERSAL=1 ./build-app.sh`

Expected: exit status 0 and `build/NotificationNanny.app` exists.

- [ ] **Step 2: Verify both architectures in the generated executable**

Run:

```bash
architectures="$(lipo -archs build/NotificationNanny.app/Contents/MacOS/NotificationNanny)"
test "$architectures" = "arm64 x86_64" -o "$architectures" = "x86_64 arm64"
printf '%s\n' "$architectures"
```

Expected: exit status 0 and output containing both `arm64` and `x86_64`.

- [ ] **Step 3: Run the Swift test suite**

Run: `swift test`

Expected: exit status 0 with all test cases passing.
