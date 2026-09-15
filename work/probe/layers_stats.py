"""Read-only forensic statistics over picture-layers.json.

1. Bottom-void test: composite the layers the way the client does and measure, per
   picture, the alpha coverage of the bottom rows of the 500x350 canvas.  A real
   postcard fills its frame; empty bottom rows mean layers were mis-placed.
2. Frog-vs-scenery test: for every emitted pose layer, measure how much of the
   frog's bounding box is covered by scenery, and how far the frog's feet are
   above the lowest scenery pixel.

Usage: python work/probe/layers_stats.py
"""
import collections
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
IMAGES = os.path.join(ROOT, 'web', 'resource', 'China', 'images')
W, H = 500, 350

RES = json.load(open(os.path.join(TABLES, 'resources.json'), encoding='utf-8'))
PICS = {str(r['id']): r for r in json.load(
    open(os.path.join(TABLES, 'Picture.json'), encoding='utf-8'))}
LAYERS = json.load(open(os.path.join(ROOT, 'engine', 'data', 'picture-layers.json'),
                        encoding='utf-8'))

ATMOS = ('sky', 'cloud', 'mou', 'bird', 'firefly', 'sun', 'moon', 'star', 'rain',
         'snow', 'wind', 'light', 'lamp_glow')


def load(rid):
    p = RES.get(str(rid))
    if not p:
        return None, None
    fp = os.path.join(IMAGES, p + '.png')
    if not os.path.exists(fp):
        return None, p
    return Image.open(fp).convert('RGBA'), p


def main():
    bottom_void = []
    content_bottoms = []
    rows = []
    for pid, rec in LAYERS.items():
        canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        poses = []
        scenery_low = 0
        for l in rec['layers']:
            rid, x, y = l['layer']
            im, path = load(rid)
            if im is None:
                continue
            canvas.alpha_composite(im, (int(x), int(y)))
            if 'scale' in l:
                poses.append((int(rid), path, int(x), int(y), im.width, im.height))
            else:
                scenery_low = max(scenery_low, min(H, int(y) + im.height))
        a = canvas.getchannel('A')
        # coverage of the bottom 10 rows and of the bottom 20% of the canvas
        bot10 = a.crop((0, H - 10, W, H))
        cov_bot10 = sum(1 for v in bot10.getdata() if v > 8) / float(W * 10)
        bot20 = a.crop((0, int(H * 0.8), W, H))
        cov_bot20 = sum(1 for v in bot20.getdata() if v > 8) / float(W * (H - int(H * 0.8)))
        # lowest row that is at least 30% covered
        lowest = -1
        for yy in range(H - 1, -1, -1):
            rowpx = [a.getpixel((xx, yy)) for xx in range(0, W, 5)]
            if sum(1 for v in rowpx if v > 8) / float(len(rowpx)) >= 0.30:
                lowest = yy
                break
        content_bottoms.append(lowest)
        rows.append((pid, rec['name'], cov_bot10, cov_bot20, lowest, scenery_low, poses))
        if cov_bot10 < 0.5:
            bottom_void.append((pid, rec['name'], cov_bot10, cov_bot20, lowest))

    print('=== pictures analysed: %d ===' % len(rows))
    print()
    print('=== A. BOTTOM-VOID TEST (bottom 10 rows of the 500x350 canvas) ===')
    print('pictures whose bottom 10 rows are <50%% covered: %d / %d (%.1f%%)'
          % (len(bottom_void), len(rows), 100.0 * len(bottom_void) / len(rows)))
    hist = collections.Counter()
    for _, _, c10, c20, low, _, _ in rows:
        hist['bottom10 coverage == 0' if c10 == 0 else
             'bottom10 coverage < 50%' if c10 < 0.5 else
             'bottom10 coverage >= 50%'] += 1
    for k, v in hist.most_common():
        print('   %-30s %d' % (k, v))
    print('   lowest >=30%%-covered row: min=%d  p25=%d  med=%d  max=%d'
          % (min(content_bottoms), sorted(content_bottoms)[len(rows) // 4],
             sorted(content_bottoms)[len(rows) // 2], max(content_bottoms)))
    print()
    print('  worst 15 (bottom of frame empty):')
    for pid, nm, c10, c20, low in sorted(bottom_void, key=lambda r: r[2])[:15]:
        row = PICS.get(pid, {})
        print('    pic %-6s %-24s bottom10cov=%.2f bottom20cov=%.2f lowest30%%row=%3d '
              'backImage=%s' % (pid, nm, c10, c20, low,
                                json.dumps(row.get('backImage'), ensure_ascii=False)[:90]))

    print()
    print('=== B. FROG-VS-SCENERY (per emitted pose layer) ===')
    # for each picture, where is the scenery content and where is the frog
    bad = 0
    tot = 0
    samples = []
    for pid, nm, c10, c20, low, scenery_low, poses in rows:
        for rid, path, x, y, w, h in poses:
            tot += 1
            feet = y + h
            # frog fully above the lowest scenery pixel?
            if feet < scenery_low - 5:
                bad += 1
                samples.append((pid, nm, rid, path, x, y, w, h, feet, scenery_low))
    print('pose layers: %d ; frog feet strictly ABOVE the lowest scenery pixel: %d'
          % (tot, bad))
    print()
    print('=== C. FROG LAYER y HAS NO RELATION TO SCENERY (all scenery at (0,0)) ===')
    ys = []
    for pid, nm, c10, c20, low, scenery_low, poses in rows:
        for rid, path, x, y, w, h in poses:
            ys.append((y, h, pid, nm))
    ys.sort()
    print('   frog layer y: min=%d p25=%d med=%d p75=%d max=%d'
          % (ys[0][0], ys[len(ys) // 4][0], ys[len(ys) // 2][0],
             ys[3 * len(ys) // 4][0], ys[-1][0]))
    print('   frog layers with y < 175 (upper half): %d / %d'
          % (sum(1 for v in ys if v[0] < 175), len(ys)))
    print('   frog layers with y < 100 (top third): %d / %d'
          % (sum(1 for v in ys if v[0] < 100), len(ys)))
    print()
    print('   sample (pic, name, poseRes, x, y, feetY, lowest scenery pixel):')
    for s in samples[:12]:
        print('     %-6s %-22s res=%-6s x=%4d y=%4d feet=%4d sceneryLowest=%4d'
              % (s[0], s[1], s[2], s[4], s[5], s[8], s[9]))


if __name__ == '__main__':
    main()
