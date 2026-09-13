#!/usr/bin/env python3
"""Measure the baked calendar page: size, and the pixel bands that contain ink.

The month pages (resource/China/images/Scene/Calendar/calendar_N.png) are
pre-rendered 2023 calendars, so before deciding how to overlay a real one it
helps to know exactly where the title / weekday row / date rows / year sit.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import sys

from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else \
    str(PROJECT_ROOT) + "/work/run/web/resource/China/images/Scene/Calendar/calendar_9.png"

im = Image.open(path).convert("RGB")
w, h = im.size
print("size: %dx%d  mode=%s" % (w, h, im.mode))
px = im.load()


def ink(x, y):
    r, g, b = px[x, y]
    # anything clearly darker than the paper background
    return (r + g + b) / 3 < 150


rows = []
for y in range(h):
    n = sum(1 for x in range(w) if ink(x, y))
    rows.append(n)

# group consecutive rows with ink into bands
bands = []
cur = None
for y, n in enumerate(rows):
    if n > 0:
        if cur is None:
            cur = [y, y, 0]
        cur[1] = y
        cur[2] = max(cur[2], n)
    else:
        if cur is not None and cur[1] - cur[0] >= 1:
            bands.append(tuple(cur))
        cur = None
if cur is not None:
    bands.append(tuple(cur))

print("ink row-bands (y0,y1,maxcount):")
for b in bands:
    print("   %4d..%4d  max=%d" % b)

cols = []
for x in range(w):
    n = sum(1 for y in range(h) if ink(x, y))
    cols.append(n)
cbands = []
cur = None
for x, n in enumerate(cols):
    if n > 0:
        if cur is None:
            cur = [x, x, 0]
        cur[1] = x
        cur[2] = max(cur[2], n)
    else:
        if cur is not None and cur[1] - cur[0] >= 1:
            cbands.append(tuple(cur))
        cur = None
if cur is not None:
    cbands.append(tuple(cur))
print("ink col-bands (x0,x1,maxcount):")
for b in cbands:
    print("   %4d..%4d  max=%d" % b)
