"""Read-only: 2x2 comparison per picture —
   (A) OURS as shipped
   (B) OFFICIAL scenery (recovered from the gif spine) + OFFICIAL frog anchor
   (C) our scenery + official frog anchor      -> frog floats in the sky
   (D) official scenery + our frog layer       -> frog floats in the sky

Usage: python work/probe/compare_layout_probe.py <picId> <out.png>
"""
import collections
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
IMAGES = os.path.join(ROOT, 'web', 'resource', 'China', 'images')
RES = json.load(open(os.path.join(TABLES, 'resources.json'), encoding='utf-8'))
PICS = {str(r['id']): r for r in json.load(
    open(os.path.join(TABLES, 'Picture.json'), encoding='utf-8'))}
OURS = json.load(open(os.path.join(ROOT, 'engine', 'data', 'picture-layers.json'),
                      encoding='utf-8'))
W, H = 500, 350

# official y (top-left) recovered by work/probe/official_layout_probe.py from the
# gif spine files; values are for picture 104 (back_n_beach3), gif_2.
OFFICIAL_104 = [
    ('sky04', 0.0),
    ('mou_back01', 76.25),
    ('sea01', 98.75),
    ('flower01', 106.36),
    ('earth', 244.63),
]
OFFICIAL_100 = [           # gif_1 is a redraw, so only the band structure transfers
    ('sky05', 0.0),
    ('mou_back03', 218.88),   # gif slot `shan`
    ('roof01', 268.50),       # gif slot `zg_1` (500x83, bottom of frame)
]
OFFICIAL = {'104': OFFICIAL_104, '100': OFFICIAL_100}


def by_base(name):
    """resId of a resource whose basename is `name` (lowest id wins)."""
    ids = [int(k) for k, v in RES.items() if os.path.basename(v) == name]
    return min(ids) if ids else None


def load(rid):
    p = RES.get(str(rid))
    if not p:
        return None
    fp = os.path.join(IMAGES, p + '.png')
    return Image.open(fp).convert('RGBA') if os.path.exists(fp) else None


def compose(items, label):
    """items: [(rid, x, y)]"""
    c = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for rid, x, y in items:
        im = load(rid)
        if im is not None:
            c.alpha_composite(im, (int(round(x)), int(round(y))))
    bg = Image.new('RGBA', (W, H), (255, 255, 255, 255))
    bg.alpha_composite(c)
    d = ImageDraw.Draw(bg)
    d.rectangle([0, 0, W - 1, 15], fill=(0, 0, 0))
    d.text((4, 3), label, fill=(255, 255, 0))
    return bg.convert('RGB')


def main():
    pid = sys.argv[1]
    rec = OURS[pid]
    row = PICS[pid]
    fp = row['frogPos']
    pose = [l for l in rec['layers'] if 'scale' in l]
    scene = [l for l in rec['layers'] if 'scale' not in l]
    assert len(pose) == 1, pose
    prid, px, py = pose[0]['layer']
    pim = load(prid)
    pw, ph = (pim.width, pim.height) if pim else (0, 0)

    # our scenery list, in table order, mapped onto the official y table by name
    scene_items = [(l['layer'][0], l['layer'][1], l['layer'][2]) for l in scene]
    off = OFFICIAL.get(pid, [])
    off_items = []
    for name, y in off:
        rid = by_base(name)
        if rid is not None:
            off_items.append((rid, 0, y))
    # keep every other scenery asset of ours that is not in the official table
    known = {by_base(n) for n, _ in off}
    tail = [it for it in scene_items if it[0] not in known]

    official_frog = (250 + fp['x'] - pw / 2.0, 350 + fp['y'] - ph)
    our_frog = (px, py)

    tiles = [
        compose(scene_items, 'A  OURS as shipped   frog top-left=(%d,%d)' % (px, py)),
        compose(off_items + tail + [(prid, official_frog[0], official_frog[1])],
                'B  OFFICIAL layout (gif spine)  frog=(%d,%d)' % official_frog),
        compose(scene_items + [(prid, official_frog[0], official_frog[1])],
                'C  our scenery + official frog'),
        compose(off_items + tail + [(prid, px, py)],
                'D  official scenery + our frog layer'),
    ]
    out = Image.new('RGB', (2 * W, 2 * H), (30, 30, 30))
    for i, t in enumerate(tiles):
        out.paste(t, ((i % 2) * W, (i // 2) * H))
    out.save(sys.argv[2])
    print('picture %s (%s) frogPos=%s pose res=%s size=%dx%d'
          % (pid, row['name'], fp, prid, pw, ph))
    print('  our frog top-left      = (%d, %d)' % (px, py))
    print('  official frog top-left = (%.1f, %.1f)   [= 250+x-w/2 , 350+y-h]'
          % official_frog)
    print('  official scenery y     = %s' % json.dumps(off))
    print('  wrote %s' % sys.argv[2])


if __name__ == '__main__':
    main()
