"""Read-only forensic renderer: composite picture-layers.json exactly like the
client does (bitmap at (layer[1], layer[2]), canvas 500x350, array order = draw
order) and emit a contact sheet so the frog's placement can be LOOKED AT.

Usage:  python work/probe/render_layers_probe.py <out.png> <picId> [picId...]
Does not write anywhere except <out.png>.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
IMAGES = os.path.join(ROOT, 'web', 'resource', 'China', 'images')
W, H = 500, 350

RES = json.load(open(os.path.join(TABLES, 'resources.json'), encoding='utf-8'))
LAYERS = json.load(open(os.path.join(ROOT, 'engine', 'data', 'picture-layers.json'),
                        encoding='utf-8'))
PICS = {str(r['id']): r for r in json.load(
    open(os.path.join(TABLES, 'Picture.json'), encoding='utf-8'))}
POSES = set()


def pose_ids():
    """Which resIds this build emitted with a 'scale' key (its own pose marker)."""
    for rec in LAYERS.values():
        for l in rec['layers'] + rec.get('travelers', []):
            if 'scale' in l:
                POSES.add(int(l['layer'][0]))


pose_ids()


def render(pid):
    rec = LAYERS.get(str(pid))
    if not rec:
        return None
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    used = []
    for l in rec['layers']:
        rid, x, y = l['layer']
        path = RES.get(str(rid))
        if not path:
            used.append((rid, '?NOPATH', x, y, None, 'pose' if 'scale' in l else ''))
            continue
        fp = os.path.join(IMAGES, path + '.png')
        if not os.path.exists(fp):
            used.append((rid, path, x, y, 'NOFILE', 'pose' if 'scale' in l else ''))
            continue
        im = Image.open(fp).convert('RGBA')
        canvas.alpha_composite(im, (int(x), int(y)))
        used.append((rid, path.split('/')[-1], x, y, im.size,
                     'POSE' if 'scale' in l else ''))
    return canvas, used


def main():
    out = sys.argv[1]
    pids = sys.argv[2:] or ['100', '101', '102', '103']
    cols = min(4, len(pids))
    rows = (len(pids) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * W, rows * (H + 18)), (28, 28, 28))
    dr = ImageDraw.Draw(sheet)
    for i, p in enumerate(pids):
        r = render(p)
        if not r:
            print('picture %s: NO LAYERS' % p)
            continue
        im, used = r
        bg = Image.new('RGBA', (W, H), (255, 255, 255, 255))
        bg.alpha_composite(im)
        ox, oy = (i % cols) * W, (i // cols) * (H + 18)
        sheet.paste(bg.convert('RGB'), (ox, oy))
        row = PICS.get(p, {})
        dr.text((ox + 4, oy + H + 2),
                'pic %s %s type=%s frogPos=%s' % (
                    p, row.get('name'), row.get('type'),
                    json.dumps(row.get('frogPos'), separators=(',', ':'))),
                fill=(255, 255, 255))
        print('--- picture %s (%s) ---' % (p, row.get('name')))
        for rid, nm, x, y, sz, tag in used:
            print('   %-10s %-24s (%4d,%4d) size=%s %s' % (rid, nm, x, y, sz, tag))
    sheet.save(out)
    print('wrote %s' % out)


if __name__ == '__main__':
    main()
