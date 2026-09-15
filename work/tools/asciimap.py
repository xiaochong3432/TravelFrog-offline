#!/usr/bin/env python3
"""Render a screenshot as a coarse ASCII colour map.

Why: OCR of a game screenshot is unreliable here (UI banners overlap the window,
translucent dim layers shift every colour), and this project has already been
burned by tools that "quietly give a plausible wrong answer". A character map
shows the actual layout -- where a block of ink is, how wide a panel is, which
row a glyph sits in -- without any model in the loop.

Usage:
    python tools/asciimap.py shots/cal13.png [--cols 90] [--crop x0,y0,x1,y1]

Legend:  ' ' white/pale   '.' light grey   ':' mid tone   '#' dark ink
         '+' warm/pink     'g' green        '@' very dark
"""
import argparse

from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("path")
ap.add_argument("--cols", type=int, default=90)
ap.add_argument("--crop", default=None, help="x0,y0,x1,y1 in pixels")
args = ap.parse_args()

im = Image.open(args.path).convert("RGB")
if args.crop:
    x0, y0, x1, y1 = [int(v) for v in args.crop.split(",")]
    im = im.crop((x0, y0, x1, y1))
W, H = im.size
px = im.load()

cw = max(1, W // args.cols)
ch = cw * 2                      # character cells are about twice as tall as wide
rows = max(1, H // ch)
print("%s  %dx%d -> %d cols x %d rows (cell %dx%d)" % (args.path, W, H, args.cols, rows, cw, ch))

for r in range(rows):
    line = []
    for c in range(args.cols):
        tot = [0, 0, 0]
        n = 0
        for y in range(r * ch, min(H, (r + 1) * ch), 2):
            for x in range(c * cw, min(W, (c + 1) * cw)):
                p = px[x, y]
                tot[0] += p[0]
                tot[1] += p[1]
                tot[2] += p[2]
                n += 1
        if not n:
            line.append(' ')
            continue
        R, G, B = tot[0] / n, tot[1] / n, tot[2] / n
        lum = (R + G + B) / 3
        if R - B > 25 and R > 150:                       # warm / pink
            line.append('+')
        elif G - R > 18 and G - B > 18:                  # green
            line.append('g')
        elif lum > 235:
            line.append(' ')
        elif lum > 205:
            line.append('.')
        elif lum > 165:
            line.append(':')
        elif lum > 100:
            line.append('#')
        else:
            line.append('@')
    print("%3d|%s|" % (r, ''.join(line)))
