#!/usr/bin/env python3
"""Turn the flat artwork for the menu-bar bell into template PNGs.

Source art is black-on-white JPEG, so this keys white out to transparency and
keeps the glyph black — the shape AppKit needs for `isTemplate = true`, where
only the alpha channel is read and the system recolours it per appearance.

Both states are cropped with one shared box so the bell stays registered
between them: the slash extends past the bell rather than shrinking it.

Run: python3 scripts/extract-glyphs.py
"""

from pathlib import Path
from PIL import Image

SRC = Path.home() / "Downloads"
OUT = Path(__file__).resolve().parent.parent / "Resources" / "Glyphs"
PAIRS = [("hey claude 2.jpeg", "bell-nanny.png"),
         ("hey claude 1.jpeg", "bell-nanny-slash.png")]

CANVAS = 512      # generous; consumers scale down
INSET = 0.94      # fraction of canvas the artwork spans

# JPEG leaves noise in the white field, so don't key on pure white: ramp
# luminance 200->0 alpha and 100->full. Keeps edge antialiasing, drops haze.
LUM_CLEAR, LUM_SOLID = 200, 100


def alpha_from(path):
    grey = Image.open(path).convert("L")
    return grey.point(
        lambda l: 255 if l <= LUM_SOLID
        else 0 if l >= LUM_CLEAR
        else int(255 * (LUM_CLEAR - l) / (LUM_CLEAR - LUM_SOLID))
    )


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    alphas = {out: alpha_from(SRC / src) for src, out in PAIRS}

    # Shared square crop box: union of both glyphs' ink, squared about its centre.
    boxes = [a.getbbox() for a in alphas.values()]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    half = max(x1 - x0, y1 - y0) / 2
    box = (round(cx - half), round(cy - half), round(cx + half), round(cy + half))
    print(f"shared crop {box}  ({box[2]-box[0]}x{box[3]-box[1]}px)")

    inner = round(CANVAS * INSET)
    for name, alpha in alphas.items():
        art = alpha.crop(box).resize((inner, inner), Image.LANCZOS)
        canvas = Image.new("L", (CANVAS, CANVAS), 0)
        off = (CANVAS - inner) // 2
        canvas.paste(art, (off, off))

        # Black ink, shape carried entirely by alpha.
        img = Image.merge("RGBA", (Image.new("L", canvas.size, 0),) * 3 + (canvas,))
        img.save(OUT / name)
        cov = sum(canvas.tobytes()) / (255 * CANVAS * CANVAS)
        print(f"wrote {name}  {CANVAS}x{CANVAS}  ink coverage {cov:.1%}")


if __name__ == "__main__":
    main()
