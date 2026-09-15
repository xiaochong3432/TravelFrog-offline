#!/usr/bin/env python3
"""Pixel-level analysis of a screenshot: is the scene area really empty?"""
import sys, collections
from PIL import Image

p = sys.argv[1]
im = Image.open(p).convert("RGB")
w, h = im.size
print(f"{p}: {w}x{h}")

px = im.load()

# global colour census (sampled)
c = collections.Counter()
for y in range(0, h, 4):
    for x in range(0, w, 4):
        c[px[x, y]] += 1
print("\ntop colours (sampled every 4px):")
for col, n in c.most_common(10):
    print(f"  {col}  {n * 100.0 / sum(c.values()):5.1f}%")

# central region only (avoid the UI strips)
x0, x1 = int(w * 0.15), int(w * 0.75)
y0, y1 = int(h * 0.25), int(h * 0.70)
cc = collections.Counter()
for y in range(y0, y1, 3):
    for x in range(x0, x1, 3):
        cc[px[x, y]] += 1
print(f"\ncentral region {x0},{y0}..{x1},{y1}: {len(cc)} distinct colours")
for col, n in cc.most_common(8):
    print(f"  {col}  {n * 100.0 / sum(cc.values()):5.1f}%")

# bounding box of anything that is not the dominant colour
dom = cc.most_common(1)[0][0]
minx, miny, maxx, maxy = w, h, -1, -1
for y in range(0, h, 3):
    for x in range(0, w, 3):
        if px[x, y] != dom:
            minx = min(minx, x); maxx = max(maxx, x)
            miny = min(miny, y); maxy = max(maxy, y)
print(f"\ndominant colour in centre: {dom}")
print(f"non-dominant bbox: ({minx},{miny})..({maxx},{maxy})")
