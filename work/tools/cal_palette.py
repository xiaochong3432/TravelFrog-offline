#!/usr/bin/env python3
"""Sample the dominant colours of a baked calendar page so a replacement drawn
at runtime can match the game's palette instead of inventing one."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import collections
import sys

from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else \
    str(PROJECT_ROOT) + "/work/run/web/resource/China/images/Scene/Calendar/calendar_9.png"
im = Image.open(path).convert("RGB")
w, h = im.size
px = im.load()

counts = collections.Counter()
for y in range(0, h, 2):
    for x in range(0, w, 2):
        counts[px[x, y]] += 1

print("size %dx%d" % (w, h))
print("top colours (r,g,b) count  hex:")
for c, n in counts.most_common(12):
    print("   %-16s %6d  #%02x%02x%02x" % (str(c), n, c[0], c[1], c[2]))

# the darkest cluster = the printed digits
dark = [(c, n) for c, n in counts.items() if sum(c) / 3 < 120]
dark.sort(key=lambda t: -t[1])
print("darkest common (digit ink):")
for c, n in dark[:6]:
    print("   %-16s %6d  #%02x%02x%02x" % (str(c), n, c[0], c[1], c[2]))

print("samples:", [px[x, y] for x, y in [(5, 5), (w // 2, 5), (5, h // 2), (w // 2, h - 5)]])
