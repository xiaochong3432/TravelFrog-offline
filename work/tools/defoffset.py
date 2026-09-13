#!/usr/bin/env python3
"""Print exact character offsets of `prototype.<name>=function` definitions."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, sys

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for name in sys.argv[1:]:
    pat = r'prototype\.' + re.escape(name) + r'\s*=\s*function'
    hits = [m.start() for m in re.finditer(pat, d)]
    print(f"{name:26s} {hits}")
