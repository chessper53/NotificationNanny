#!/usr/bin/env python3
"""Scores banner replicas against the real banner captured by lab.swift.

    score.py [--appearance dark|light] [-v] [--sheet] NAME...

Prints the mean absolute pixel error (0 to 255, lower is better) per region,
averaged over every backdrop both captures share:

    full   the whole banner plus a few points of surroundings
    bg     plain glass, away from the text and icon
    text   title and body
    icon   the app icon

--sheet also writes <out>/sheet-APPEARANCE-NAME.png: real, replica and the difference
(tripled) side by side for each backdrop.

Needs Pillow and NumPy.
"""
import argparse, os, sys
import numpy as np
from PIL import Image

OUT = os.environ.get('BANNER_LAB_OUT', 'build/banner-lab')
M = 30  # capture margin around the banner, see lab.swift


def load(path):
    return np.asarray(Image.open(path).convert('RGB')).astype(float)


def regions(w, h):
    return {
        'full': (M - 6, M - 6, M + w + 6, M + h + 6),
        'bg':   (M + 180, M + 6, M + w - 30, M + h - 6),
        'text': (M + 56, M + 10, M + 170, M + h - 10),
        'icon': (M + 10, (M * 2 + h) // 2 - 19, M + 48, (M * 2 + h) // 2 + 19),
    }


def err(a, b, r):
    x0, y0, x1, y1 = r
    return np.abs(a[y0:y1, x0:x1] - b[y0:y1, x0:x1]).mean()


def pairs(cap, name):
    for f in sorted(os.listdir(cap)):
        prefix = f'cand-{name}-'
        if f.startswith(prefix):
            bd = f[len(prefix):-4]
            real = os.path.join(cap, f'real-{bd}.png')
            if os.path.exists(real):
                yield bd, real, os.path.join(cap, f)


def score(cap, name, verbose):
    rows = []
    for bd, real, cand in pairs(cap, name):
        r, c = load(real), load(cand)
        if r.shape != c.shape:
            continue
        h, w = r.shape[0] - 2 * M, r.shape[1] - 2 * M
        e = {k: err(r, c, reg) for k, reg in regions(w, h).items()}
        rows.append(e)
        if verbose:
            print(f'    {bd:9s} ' + '  '.join(f'{k} {v:6.2f}' for k, v in e.items()))
    if not rows:
        return None
    return {k: float(np.mean([r[k] for r in rows])) for k in rows[0]}


def sheet(cap, name, appearance):
    tiles = []
    for bd, real, cand in pairs(cap, name):
        r = Image.open(real).convert('RGB')
        c = Image.open(cand).convert('RGB')
        box = (M - 10, M - 10, r.width - M + 10, r.height - M + 10)
        r, c = r.crop(box), c.crop(box)
        d = np.clip(np.abs(np.asarray(r).astype(int) - np.asarray(c).astype(int)) * 3, 0, 255)
        tiles.append((r, c, Image.fromarray(d.astype('uint8'))))
    if not tiles:
        return
    w, h = tiles[0][0].size
    out = Image.new('RGB', (w * 3 + 20, (h + 5) * len(tiles)), (255, 0, 255))
    for i, row in enumerate(tiles):
        for j, im in enumerate(row):
            out.paste(im, (j * (w + 10), i * (h + 5)))
    path = os.path.join(OUT, f'sheet-{appearance}-{name}.png')
    out.resize((out.width * 2, out.height * 2), Image.NEAREST).save(path)
    print(f'wrote {path}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--appearance', default='dark', choices=['dark', 'light'])
    ap.add_argument('-v', action='store_true')
    ap.add_argument('--sheet', action='store_true')
    ap.add_argument('names', nargs='+')
    a = ap.parse_args()
    cap = os.path.join(OUT, 'cap', a.appearance)
    results = []
    for n in a.names:
        s = score(cap, n, a.v)
        if s is None:
            print(f'{n}: no captures with a matching real banner in {cap}', file=sys.stderr)
            continue
        results.append((n, s))
        if a.sheet:
            sheet(cap, n, a.appearance)
    for n, s in sorted(results, key=lambda x: x[1]['full']):
        print(f'{n:24s} ' + '  '.join(f'{k} {v:6.2f}' for k, v in s.items()))


if __name__ == '__main__':
    main()
