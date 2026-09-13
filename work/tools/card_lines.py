#!/usr/bin/env python3
"""Locate the two text lines on the annual-review title card.

The card (summary_page1_1.png) is a solid dark-olive rectangle with text drawn in
the SAME dark olive but carrying a thick WHITE halo. So the text is findable as
near-white pixels inside the card, and clustering them by row gives the exact
bounding boxes needed to re-draw the card with a different year.

    python tools/card_lines.py <png>
"""
import sys

from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else \
    r"H:\AI\frog\work\run\web\resource\China\images\Scene\YearSummary\Bg_ui\summary_page1_1.png"
im = Image.open(path).convert("RGB")
W, H = im.size
px = im.load()

rows = []
for y in range(H):
    xs = [x for x in range(W) if min(px[x, y]) > 225]
    rows.append((y, len(xs), (min(xs), max(xs)) if xs else None))

print("%s %dx%d" % (path, W, H))
bands = []
cur = None
for y, n, ext in rows:
    if n > 2:
        if cur is None:
            cur = [y, y, ext]
        cur[1] = y
        cur[2] = (min(cur[2][0], ext[0]), max(cur[2][1], ext[1]))
    else:
        if cur is not None and cur[1] - cur[0] >= 2:
            bands.append(tuple(cur))
        cur = None
if cur is not None:
    bands.append(tuple(cur))

print("white-halo bands (y0..y1, x0..x1):")
for y0, y1, (x0, x1) in bands:
    print("   y %3d..%3d (h=%3d)   x %3d..%3d (w=%3d)" % (y0, y1, y1 - y0 + 1, x0, x1, x1 - x0 + 1))
