#!/usr/bin/env python3
"""Locate the white pill 'start' button in a title-screen screenshot."""
import sys
from PIL import Image

p = sys.argv[1]
im = Image.open(p).convert("RGB")
w, h = im.size
px = im.load()
print(f"{p}: {w}x{h}")

# The button is a large mostly-white region with a dark border, in the middle band.
best = None
ys = range(int(h * 0.30), int(h * 0.75), 2)
rows = []
for y in ys:
    run = 0
    start = None
    for x in range(w):
        r, g, b = px[x, y]
        white = r > 235 and g > 235 and b > 235
        if white:
            if start is None:
                start = x
            run += 1
        else:
            if run > 0 and start is not None:
                rows.append((y, start, run))
            run = 0
            start = None
    if run > 60 and start is not None:
        rows.append((y, start, run))

# keep the widest contiguous white runs (candidate button rows)
rows.sort(key=lambda t: -t[2])
print("widest white runs (y, xStart, width):")
for t in rows[:12]:
    print("   ", t)
if rows:
    y, xs, wd = rows[0]
    print(f"\nbutton candidate: centre ~ ({xs + wd // 2}, {y})  width={wd}")
