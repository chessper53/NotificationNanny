#!/usr/bin/env python3
"""Check that local site assets exist, ignoring HTML comments. Deployment serves the directory
verbatim."""

import re
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / "site"
INDEX = SITE / "index.html"

SKIP_PREFIXES = ("http://", "https://", "//", "#", "mailto:", "data:", "tel:")


def main() -> int:
    html = INDEX.read_text(encoding="utf-8")
    stripped = re.sub(r"<!--.*?-->", "", html, flags=re.DOTALL)

    referenced = set()
    for attribute in ("src", "href"):
        for match in re.finditer(rf'\s{attribute}="([^"]+)"', stripped):
            referenced.add(match.group(1))
    # <source srcset> may list several candidates ("a.webp 1x, b.webp 2x").
    for match in re.finditer(r'\ssrcset="([^"]+)"', stripped):
        for candidate in match.group(1).split(","):
            if candidate.strip():
                referenced.add(candidate.strip().split()[0])

    missing = []
    for reference in sorted(referenced):
        if reference.startswith(SKIP_PREFIXES) or not reference.strip():
            continue
        target = reference.split("?", 1)[0].split("#", 1)[0]
        if not target:
            continue
        if not (SITE / target).exists():
            missing.append(target)

    if missing:
        print("::error::site/index.html references files that do not exist:")
        for target in missing:
            print(f"  site/{target}")
        print("Add the file, or comment out the markup until it exists.")
        return 1

    checked = len(referenced)
    print(f"All {checked} referenced paths resolve (commented-out markup ignored).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
