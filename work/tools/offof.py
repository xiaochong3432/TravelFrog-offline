#!/usr/bin/env python3
"""Print offsets of a list of literal substrings in main.min.js (char offsets)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import sys

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for line in open(sys.argv[1], encoding="utf8"):
    p = line.rstrip("\n")
    if not p:
        continue
    hits, i = [], d.find(p)
    while i >= 0 and len(hits) < 6:
        hits.append(i)
        i = d.find(p, i + 1)
    print("%-52s %s" % (p[:50], hits))
