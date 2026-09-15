#!/usr/bin/env python3
"""Crop and magnify a small art asset so it can actually be read.

    python tools/upscale.py <png> <out.png> [--scale 3] [--crop x0,y0,x1,y1]
"""
import argparse

from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("path")
ap.add_argument("out")
ap.add_argument("--scale", type=int, default=3)
ap.add_argument("--crop", default=None)
args = ap.parse_args()

im = Image.open(args.path).convert("RGB")
if args.crop:
    x0, y0, x1, y1 = [int(v) for v in args.crop.split(",")]
    im = im.crop((x0, y0, x1, y1))
im = im.resize((im.width * args.scale, im.height * args.scale), Image.NEAREST)
im.save(args.out)
print("wrote %s (%dx%d)" % (args.out, im.width, im.height))
