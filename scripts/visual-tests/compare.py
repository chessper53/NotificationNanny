#!/usr/bin/env python3
"""Compare PNG directories; write a portable HTML report and amplified differences."""
import argparse
import html
import json
from pathlib import Path
import shutil

from PIL import Image, ImageChops, ImageStat


def compare(baseline, current, output, tolerance=8):
    output.mkdir(parents=True, exist_ok=True)
    names = sorted({p.name for folder in (baseline, current) for p in folder.glob('*.png')})
    if not names:
        raise ValueError('No PNG captures found')
    rows = []
    for name in names:
        row = {'name': name, 'status': 'unchanged'}
        for label, folder in [('baseline', baseline), ('current', current)]:
            source = folder / name
            if source.exists():
                target = output / label / name
                target.parent.mkdir(exist_ok=True)
                shutil.copyfile(source, target)
        if not (baseline / name).exists():
            row['status'] = 'added'
        elif not (current / name).exists():
            row['status'] = 'missing'
        else:
            with Image.open(baseline / name) as a, Image.open(current / name) as b:
                if a.size != b.size:
                    row['status'] = 'resized'
                else:
                    diff = ImageChops.difference(a.convert('RGBA'), b.convert('RGBA'))
                    channels = diff.split()
                    maximum = channels[0]
                    for channel in channels[1:]:
                        maximum = ImageChops.lighter(maximum, channel)
                    histogram = maximum.histogram()
                    changed = sum(histogram[tolerance + 1:])
                    row['changed_pixels'] = changed
                    row['changed_percent'] = round(100 * changed / (a.width * a.height), 4)
                    row['mean_error'] = round(sum(ImageStat.Stat(diff).mean) / 4, 4)
                    if changed:
                        row['status'] = 'changed'
                        diff.convert('RGB').point(lambda x: min(255, x * 4)).save(output / ('diff-' + name))
        rows.append(row)
    (output / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
    cards = []
    for row in rows:
        name = html.escape(row['name'], quote=True)
        images = []
        for label, path in [('Baseline', 'baseline/' + name), ('Current', 'current/' + name), ('Difference ×4', 'diff-' + name)]:
            if (output / html.unescape(path)).exists():
                images.append(f'<figure><figcaption>{label}</figcaption><a href="{path}"><img src="{path}" loading="lazy"></a></figure>')
        cards.append(f'<section><h2>{name}: {row["status"]}</h2><p>Changed pixels: {row.get("changed_percent", "n/a")}%</p><div>{"".join(images)}</div></section>')
    changed = sum(row['status'] != 'unchanged' for row in rows)
    (output / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Settings visual review</title>'
        '<style>body{font:14px system-ui;margin:24px;background:#eee;color:#222}section{border-top:1px solid #aaa}section div{display:flex;gap:12px}figure{margin:0;flex:1;min-width:0}img{width:100%;height:auto}figcaption{margin:8px 0}</style>'
        f'<h1>Settings visual review</h1><p>{changed} of {len(rows)} captures differ. Channel tolerance: {tolerance}/255. Review intentional changes; this report does not approve them.</p>' + ''.join(cards))
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('current', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--tolerance', type=int, default=8)
    parser.add_argument('--fail-on-change', action='store_true')
    args = parser.parse_args()
    if not 0 <= args.tolerance <= 255:
        parser.error('tolerance must be between 0 and 255')
    for folder in (args.baseline, args.current):
        if not folder.is_dir():
            parser.error(f'Capture directory does not exist: {folder}')
    # Output must be separate: copying into an input can corrupt later comparisons.
    for folder in (args.baseline, args.current):
        if args.output.resolve() == folder.resolve() or folder.resolve() in args.output.resolve().parents or args.output.resolve() in folder.resolve().parents:
            parser.error('Output and input directories must not overlap')
    if args.output.exists():
        shutil.rmtree(args.output)
    try:
        changed = compare(args.baseline, args.current, args.output, args.tolerance)
    except ValueError as error:
        parser.error(str(error))
    print(f'{changed} captures differ; report: {args.output / "index.html"}')
    return int(args.fail_on_change and changed > 0)


if __name__ == '__main__':
    raise SystemExit(main())
