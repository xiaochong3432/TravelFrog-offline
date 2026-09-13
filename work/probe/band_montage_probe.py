"""Read-only: show every "band" scenery asset (i.e. NOT a full 500x350 canvas)
at native size on a magenta background, so its content/extent is visible.

Usage: python work/probe/band_montage_probe.py <out.png> [resId ...]
        (no ids -> a default set drawn from picture 100/102/104/107)
"""
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
IMAGES = os.path.join(ROOT, 'web', 'resource', 'China', 'images')
RES = json.load(open(os.path.join(TABLES, 'resources.json'), encoding='utf-8'))

DEFAULT = [11, 21, 390, 36, 34, 6, 19, 18, 22, 5, 7, 8, 35, 25, 26, 27,
           2, 1, 14, 16, 20, 16]
CELLW = 520
ROWMAX = 130
WS = [int(a) for a in sys.argv[2:]] if len(sys.argv) > 2 else DEFAULT


def main():
    out_path = sys.argv[1]
    rows = []
    meta = []
    for rid in WS:
        p = RES.get(str(rid))
        fp = os.path.join(IMAGES, (p or '') + '.png')
        if not os.path.exists(fp):
            meta.append((rid, p, 'MISSING', None))
            continue
        im = Image.open(fp).convert('RGBA')
        # keep native size but shrink only if wider than the cell
        s = min(1.0, (CELLW - 10) / im.width)
        if s < 1.0:
            im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))),
                           Image.LANCZOS)
        rows.append((rid, p, im, s))
        meta.append((rid, p, Image.open(fp).size, s))

    total_h = sum(max(im.height, 12) + 16 for _, _, im, _ in rows)
    out = Image.new('RGB', (CELLW, max(1, total_h)), (255, 0, 255))
    dr = ImageDraw.Draw(out)
    y = 0
    for rid, p, im, s in rows:
        bg = Image.new('RGBA', (CELLW, im.height), (255, 0, 255, 255))
        bg.alpha_composite(im, (0, 0))
        out.paste(bg.convert('RGB'), (0, y))
        dr.text((4, y + im.height + 2), '%s %s  native=%dx%d drawn@%.2f'
                % (rid, os.path.basename(p), meta[[m[0] for m in meta].index(rid)][2][0],
                   meta[[m[0] for m in meta].index(rid)][2][1], s) if False else
                '%s %s' % (rid, os.path.basename(p)), fill=(255, 255, 255))
        y += im.height + 16
        dr.line([(0, y - 1), (CELLW, y - 1)], fill=(90, 90, 90))
    out.save(out_path)
    print('wrote %s' % out_path)
    for rid, p, sz, s in meta:
        print('   %-6s %-32s %s scaled=%.2f' % (rid, p, sz, s if s else 0))


if __name__ == '__main__':
    main()
