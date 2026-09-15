#!/usr/bin/env python3
"""Per-row ink profile of a small art asset, to find the gap between two lines.

Used for summary_page1_1.png: the annual-review title card is "2022" over
"旅行日记" as pixels, so covering ONLY the year means knowing exactly where the
year line ends and the text below begins.

    python tools/rowprofile.py <png> [--thresh 150]
"""
import argparse

from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("path")
ap.add_argument("--thresh", type=int, default=150)
args = ap.parse_args()

im = Image.open(args.path).convert("RGB")
W, H = im.size
px = im.load()
print("%s: %dx%d" % (args.path, W, H))
print("row : ink  bar")
for y in range(H):
    n = 0
    for x in range(W):
        r, g, b = px[x, y]
        if (r + g + b) / 3 < args.thresh:
            n += 1
    if y % 1 == 0:
        print("%4d: %4d %s" % (y, n, "#" * min(60, n // 4)))
