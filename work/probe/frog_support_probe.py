"""Read-only: which shipped postcards actually show the frog with NOTHING under it?

For every picture in picture-layers.json:
  * build a "solid support" mask = union of all non-pose layers whose art is NOT
    atmospheric (sky*/cloud*/mou*/bird*/fog*/sun*/moon*/star*/rain*/snow*)
  * for the emitted frog layer, look at the band of rows directly BELOW the
    frog's bottom edge (feet), same x range, height 40 px
  * if that band contains no support pixel, the frog has nothing to stand on --
    it is drawn against sky/void only.

Usage: python work/probe/frog_support_probe.py
"""
import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
IMAGES = os.path.join(ROOT, 'web', 'resource', 'China', 'images')
W, H = 500, 350

RES = json.load(open(os.path.join(TABLES, 'resources.json'), encoding='utf-8'))
PICS = {str(r['id']): r for r in json.load(
    open(os.path.join(TABLES, 'Picture.json'), encoding='utf-8'))}
OURS = json.load(open(os.path.join(ROOT, 'engine', 'data', 'picture-layers.json'),
                      encoding='utf-8'))

ATMOS = ('sky', 'cloud', 'yun', 'mou', 'bird', 'fog', 'sun', 'moon', 'star',
         'rain', 'snow', 'firefly', 'wu', 'light')


def load(rid):
    p = RES.get(str(rid))
    if not p:
        return None, None
    fp = os.path.join(IMAGES, p + '.png')
    if not os.path.exists(fp):
        return None, p
    return Image.open(fp).convert('RGBA'), os.path.basename(p)


def main():
    flying = []
    ok = 0
    skipped = 0
    for pid, rec in OURS.items():
        support = Image.new('L', (W, H), 0)
        pose = None
        for l in rec['layers']:
            rid, x, y = l['layer']
            im, base = load(rid)
            if im is None:
                continue
            if 'scale' in l:
                pose = (rid, base, int(x), int(y), im.width, im.height)
                continue
            if base.lower().startswith(ATMOS):
                continue
            a = im.getchannel('A')
            support.paste(255, (int(x), int(y)), a)
        if pose is None:
            skipped += 1
            continue
        rid, base, x, y, w, h = pose
        feet = y + h
        band = support.crop((max(0, x), min(H - 1, feet), min(W, x + w),
                             min(H, feet + 40)))
        n = sum(1 for v in band.getdata() if v > 8)
        if n == 0:
            flying.append((pid, rec['name'], PICS.get(pid, {}).get('type'),
                           base, x, y, feet, w, h))
        else:
            ok += 1
    print('pictures with a pose layer      : %d' % (len(OURS) - skipped))
    print('  frog HAS solid support below  : %d' % ok)
    print('  frog has NOTHING under its feet (drawn over sky/void): %d'
          % len(flying))
    print()
    print('frog layers placed further up than the top of the classic'
          ' ground band (y < 250 for a 350-tall frame):')
    ys = sorted((l['layer'][2], pid, rec['name'])
                for pid, rec in OURS.items() for l in rec['layers'] if 'scale' in l)
    print('  y distribution: min=%d p25=%d med=%d p75=%d max=%d'
          % (ys[0][0], ys[len(ys) // 4][0], ys[len(ys) // 2][0],
             ys[3 * len(ys) // 4][0], ys[-1][0]))
    print()
    print('examples of "frog over pure sky" (first 25):')
    print('  %-6s %-24s %-7s %-22s frog(x,y)  feet  size' % ('pic', 'name', 'type', 'pose'))
    for f in sorted(flying, key=lambda r: -r[7])[:25]:
        print('  %-6s %-24s %-7s %-22s (%3d,%3d) %4d  %dx%d'
              % (f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8]))


if __name__ == '__main__':
    main()
