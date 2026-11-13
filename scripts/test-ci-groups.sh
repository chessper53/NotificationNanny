#!/usr/bin/env bash
# Require every top level test suite to appear in a CI test group.
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
