#!/usr/bin/env python3
"""Locate the light-blue notification band in a screenshot (to compute tap coords)."""
import sys, collections
from PIL import Image

p = sys.argv[1]
im = Image.open(p).convert("RGB")
w, h = im.size
px = im.load()
print(f"{p}: {w}x{h}")

best = []
for y in range(0, h, 2):
    n = 0
    for x in range(0, w, 4):
        r, g, b = px[x, y]
        # pale blue: blue clearly dominant, bright
        if b > 200 and b - r > 18 and g > 190:
            n += 1
    if n > 40:
        best.append((y, n))

if not best:
    print("no pale-blue band found")
else:
    ys = [y for y, _ in best]
    print(f"band rows {min(ys)}..{max(ys)}  (count {len(ys)})")
    print(f"=> tap centre approx ({w//2}, {(min(ys)+max(ys))//2})")
