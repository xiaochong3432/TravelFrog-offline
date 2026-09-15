#!/usr/bin/env python3
"""Dump a CHARACTER range of main.min.js (offsets match occur.py / where_literal.py).

dump_range.py uses BYTE offsets, which drift from occur.py's char offsets in any
region containing multi-byte CJK. This helper keeps them consistent.

Usage: dump_chars.py <start_char> <end_char> <outfile>
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import sys, re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

start = int(sys.argv[1]); end = int(sys.argv[2]); out = sys.argv[3]
seg = d[start:end]
seg = re.sub(r'([;{}])', r'\1\n', seg)
open(out, "w", encoding="utf8").write(seg)
print(f"chars {start}..{end} -> {out} ({len(seg)} chars)")
