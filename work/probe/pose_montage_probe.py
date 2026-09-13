"""Read-only: montage of the pose sprites our build emits, upscaled, so their
CONTENT (frog only? frog+perch?) can be inspected.

Usage: python work/probe/pose_montage_probe.py <out.png>
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
LAYERS = json.load(open(os.path.join(ROOT, 'engine', 'data', 'picture-layers.json'),
                        encoding='utf-8'))

# collect every resId emitted as a pose, with the pictures that use it
poses = {}
for pid, rec in LAYERS.items():
    for l in rec['layers']:
        if 'scale' in l:
            poses.setdefault(int(l['layer'][0]), []).append(pid)

names = sorted(poses, key=lambda r: len(poses[r]), reverse=True)
names = names[:16]
CELL = 200
SCALE = 2
cols = 4
rows = (len(names) + cols - 1) // cols
out = Image.new('RGB', (cols * CELL, rows * (CELL + 16)), (40, 40, 40))
dr = ImageDraw.Draw(out)
for i, rid in enumerate(names):
    p = RES.get(str(rid))
    fp = os.path.join(IMAGES, (p or '') + '.png')
    ox, oy = (i % cols) * CELL, (i // cols) * (CELL + 16)
    if os.path.exists(fp):
        im = Image.open(fp).convert('RGBA')
        im = im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)
        bg = Image.new('RGBA', (CELL, CELL), (255, 255, 255, 255))
        bg.alpha_composite(im, (0, CELL - im.height if im.height < CELL else 0))
        out.paste(bg.convert('RGB'), (ox, oy))
        dr.text((ox + 3, oy + CELL + 2),
                '%s %s %dx%d n=%d' % (rid, os.path.basename(p or '?'),
                                      im.width // SCALE, im.height // SCALE,
                                      len(poses[rid])),
                fill=(255, 255, 255))
    else:
        dr.text((ox + 3, oy + 3), '%s MISSING %s' % (rid, p), fill=(255, 80, 80))
out.save(sys.argv[1])
print('wrote %s with %d pose sprites' % (sys.argv[1], len(names)))
for rid in names:
    p = RES.get(str(rid))
    fp = os.path.join(IMAGES, (p or '') + '.png')
    sz = Image.open(fp).size if os.path.exists(fp) else 'MISSING'
    print('  %-6s %-28s %-12s used by %d pictures (e.g. %s)'
          % (rid, p, sz, len(poses[rid]), poses[rid][:4]))
