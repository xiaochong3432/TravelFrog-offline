#!/usr/bin/env python3
"""Crop a region of a screenshot (for reading HUD text via vision)."""
import sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
x, y, w, h = (int(v) for v in sys.argv[3:7])
im = Image.open(src).convert("RGB")
im.crop((x, y, x + w, y + h)).resize((w * 3, h * 3), Image.LANCZOS).save(out)
print(f"{out}: {w*3}x{h*3} (from {src} {x},{y} {w}x{h})")
