#!/usr/bin/env python3
"""Regex-search main.min.js and print offsets + context to a file (UTF-8 safe).

Usage: rx.py <out.txt> <regex> [before] [after] [maxhits]
Console output is only a count, so no GBK encode errors.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, sys

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

out = sys.argv[1]
pat = sys.argv[2]
before = int(sys.argv[3]) if len(sys.argv) > 3 else 200
after = int(sys.argv[4]) if len(sys.argv) > 4 else 200
maxhits = int(sys.argv[5]) if len(sys.argv) > 5 else 20

hits = list(re.finditer(pat, d))
with open(out, "w", encoding="utf8") as f:
    f.write(f"pattern {pat!r}: {len(hits)} hits\n")
    for m in hits[:maxhits]:
        seg = d[max(0, m.start() - before):m.end() + after].replace("\n", " ")
        f.write(f"\n[{m.start()}] ...{seg}...\n")
print(f"{len(hits)} hits -> {out}")
