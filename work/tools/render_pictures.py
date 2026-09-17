"""
Render precomputed picture layers exactly the way the client does, so the
result can be LOOKED AT.

Client semantics (main.min.js):
    for layer in layers:  bitmap at (layer[1], layer[2]), draw order = array order
    canvas 500 x 350
Any layer whose (x,y) pushes it outside the canvas simply gets clipped, which is
what the client would do too -- so a bad coordinate shows up as a visibly
missing element rather than as an error.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
IMAGES = os.path.join(ROOT, 'web', 'resource', 'China', 'images')

RES = json.load(open(os.path.join(TABLES, 'resources.json'), encoding='utf-8'))
LAYERS = json.load(open(os.path.join(ROOT, 'engine', 'data', 'picture-layers.json'),
                        encoding='utf-8'))
W, H = 500, 350


def render(pid, dy=0, dx=0, only_pose=False):
    rec = LAYERS.get(str(pid))
    if not rec:
        return None
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    used = []
    for l in rec['layers']:
        rid, x, y = l['layer']
        path = RES.get(str(rid))
        if not path:
            continue
        fp = os.path.join(IMAGES, path + '.png')
        if not os.path.exists(fp):
            continue
        try:
            im = Image.open(fp).convert('RGBA')
        except Exception:
            continue
        if l.get('size'):
            im = im.resize(tuple(l['size']), Image.Resampling.LANCZOS)
        sc = l.get('scale', 1)
        if sc != 1:
            im = im.resize((max(1, int(im.width * sc)), max(1, int(im.height * sc))),
                           Image.NEAREST)
        oy = dy if (not only_pose or 'scale' in l) else 0
        ox = dx if (not only_pose or 'scale' in l) else 0
        canvas.alpha_composite(im, (int(x) + ox, int(y) + oy))
        used.append((rid, path.split('/')[-1], x, y, im.size, sc))
    return canvas, used


def sheet(pids, out, dy=0, dx=0, cols=5):
    tiles = []
    for p in pids:
        r = render(p, dy, dx)
        if not r:
            continue
        im, used = r
        bg = Image.new('RGBA', (W, H), (255, 255, 255, 255))
        bg.alpha_composite(im)
        tiles.append((p, bg, used))
    if not tiles:
        print('nothing rendered')
        return
    cols = min(cols, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    out_im = Image.new('RGB', (cols * W, rows * H), (32, 32, 32))
    for i, (p, bg, used) in enumerate(tiles):
        out_im.paste(bg.convert('RGB'), ((i % cols) * W, (i // cols) * H))
    out_im.save(out)
    print('wrote %s  (%d pictures, %dx%d)' % (out, len(tiles), out_im.width, out_im.height))
    for p, bg, used in tiles[:3]:
        print('  picture %s: %d layers' % (p, len(used)))
        for u in used:
            print('     resId=%-6s %-28s at (%4d,%4d) size %s scale %s' % u)


if __name__ == '__main__':
    dy = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    dx = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, 'contact.png')
    pids = [int(a) for a in sys.argv[4:]] or [100, 101, 102, 2000, 2001, 102, 103, 104, 105, 106]
    sheet(pids, out, dy, dx)
