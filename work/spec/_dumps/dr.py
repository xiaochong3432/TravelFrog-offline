#!/usr/bin/env python3
"""Dump a DECODED-STRING range of main.min.js (offsets match occur.py / dump_class.py)."""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import sys, re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

start = int(sys.argv[1]); end = int(sys.argv[2]); out = sys.argv[3]
seg = d[start:end]
seg = re.sub(r'([;{}])', r'\1\n', seg)
open(out, "w", encoding="utf8").write(seg)
print("chars %d..%d -> %s (%d chars)" % (start, end, out, len(seg)))
