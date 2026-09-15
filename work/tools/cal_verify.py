#!/usr/bin/env python3
"""Verify the redrawn calendar against the screenshot, without trusting OCR.

The redrawn page is pure white (255,255,255) and 553x648 in game content units,
so in the screenshot it is the largest white rectangle. From it we recover the
content->pixel scale, then predict where each day number should be and check
that ink is actually there.

Usage: python tools/cal_verify.py shots/cal13.png
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import sys

from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else str(PROJECT_ROOT) + "/work/shots/cal13.png"
im = Image.open(path).convert("RGB")
W, H = im.size
px = im.load()
print("screenshot %dx%d" % (W, H))


def is_white(x, y):
    r, g, b = px[x, y]
    return r > 246 and g > 246 and b > 246


# Find the widest run of white rows/cols to locate the page.
row_white = [sum(1 for x in range(W) if is_white(x, y)) for y in range(H)]
col_white = [sum(1 for y in range(H) if is_white(x, y)) for x in range(W)]

best_rows = [(y, n) for y, n in enumerate(row_white) if n > W * 0.5]
best_cols = [(x, n) for x, n in enumerate(col_white) if n > H * 0.3]
if not best_rows or not best_cols:
    print("!! could not locate the white page")
    sys.exit(1)

y0, y1 = best_rows[0][0], best_rows[-1][0]
x0, x1 = best_cols[0][0], best_cols[-1][0]
print("white page bbox: x %d..%d (%d)   y %d..%d (%d)" % (x0, x1, x1 - x0 + 1, y0, y1, y1 - y0 + 1))

scale = (x1 - x0 + 1) / 553.0
print("scale = %.4f px per content unit" % scale)

# In content units: page top-left is (30,244); grid top-left is (51,421);
# cell = 73x65, and each number is drawn in a cell at y offset +4, height 40.
GRID_DX = (51 - 30) * scale
GRID_DY = (421 - 244) * scale
CW = 73 * scale
CH = 65 * scale
print("grid origin in screenshot: %.1f,%.1f  cell %.1f x %.1f" % (x0 + GRID_DX, y0 + GRID_DY, CW, CH))


def ink_near(cx, cy, half):
    """count dark pixels in a box around (cx,cy)"""
    n = 0
    for y in range(max(0, int(cy - half)), min(H, int(cy + half))):
        for x in range(max(0, int(cx - half)), min(W, int(cx + half))):
            r, g, b = px[x, y]
            if (r + g + b) / 3 < 170:
                n += 1
    return n


def cell_center(col, row):
    return (x0 + GRID_DX + col * CW + CW / 2.0,
            y0 + GRID_DY + row * CH + (4 + 20) * scale)


# Expected layout for 2026-09: firstWeek=2 -> day 1 at column 1; 30 days; lead 1.
EXPECT = {}
lead = 1
prev_max = 31
for e in range(42):
    day = e - lead + 1
    if day < 1:
        label = str(prev_max + day)
    elif day > 30:
        label = str(day - 30)
    else:
        label = str(day)
    EXPECT[(e % 7, e // 7)] = label

print("\nday-number ink check (row 0 = the row holding day 1):")
bad = []
for row in range(6):
    line = []
    for col in range(7):
        cx, cy = cell_center(col, row)
        n = ink_near(cx, cy, max(3, CW * 0.28))
        lab = EXPECT.get((col, row), '?')
        mark = 'ok' if n > 8 else 'MISSING'
        if n <= 8:
            bad.append((col, row, lab))
        line.append('%s:%s(%d)' % (lab, mark, n))
    print("  row%d  %s" % (row, '  '.join(line)))

print("\nweekday header row (one row above row 0):")
for col in range(7):
    cx = x0 + GRID_DX + col * CW + CW / 2.0
    cy = y0 + GRID_DY - 46 * scale + 20 * scale
    n = ink_near(cx, cy, max(3, CW * 0.28))
    print("  col%d ink=%d %s" % (col, n, 'ok' if n > 5 else 'MISSING'))

print("\ntitle band:")
for name, cx_off in (('month', 26 + 75), ('year', 553 - 176 + 75)):
    cx = x0 + cx_off * scale
    cy = y0 + (24 + 20) * scale
    print("  %s ink=%d" % (name, ink_near(cx, cy, 30)))

print("\nRESULT: %d cells with no ink" % len(bad))
for b in bad:
    print("   missing: col%d row%d expected '%s'" % b)
