#!/usr/bin/env python3
"""Fail if site/index.html references a local file that is not committed.

pages.yml uploads site/ verbatim, and nothing else looks at what the HTML points
at, so a typo or an asset that was never added deploys as a silent 404: a broken
image, or a video player whose play button does nothing.

HTML comments are stripped before scanning, so markup staged behind a comment
(the demo clip, until the recording exists) is intentionally not required yet.
"""

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
        for match in re.finditer(rf'{attribute}="([^"]+)"', stripped):
            referenced.add(match.group(1))

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
