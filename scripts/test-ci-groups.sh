#!/usr/bin/env bash
# Every test suite in Tests/ is in one of ci.yml's test groups: a suite in none would
# silently stop running in CI. Suites are the top-level types named ...Tests.
set -euo pipefail
cd "$(dirname "$0")/.."
missing=0
for suite in $(grep -rhoE '^(@[A-Za-z]+[^\n]*\s)?(final class|class|struct) [A-Za-z0-9_]+Tests\b' Tests | grep -oE '[A-Za-z0-9_]+Tests$' | sort -u); do
    if ! grep -qE "[(|]${suite}[|)]" .github/workflows/ci.yml; then
        echo "error: $suite is in no test group in .github/workflows/ci.yml" >&2
        missing=1
    fi
done
[[ $missing == 0 ]] && echo "every test suite is in a CI group"
exit $missing
