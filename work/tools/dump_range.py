#!/usr/bin/env python3
"""Dump a BYTE range of main.min.js to a UTF-8 file (offsets match jsctx.py)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import sys, re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
raw = open(JS, "rb").read()

start = int(sys.argv[1]); end = int(sys.argv[2])
out = sys.argv[3]
seg = raw[start:end].decode("utf8", "replace")
seg = re.sub(r'([;{}])', r'\1\n', seg)
open(out, "w", encoding="utf8").write(seg)
print(f"bytes {start}..{end} -> {out} ({len(seg)} chars)")
