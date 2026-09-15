#!/usr/bin/env python3
"""Search main.min.js for CJK strings WITHOUT passing them through a shell.

`python tools/jsfind.py 与你同行` is mangled by PowerShell's code page (the pattern
arrives as GBK). Reading the patterns from this file avoids the shell entirely.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os
import re

JS = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
PATTERNS = [
    "与你同行",
    "旅行日记",
    "这一年",
    "年度总结",
]

with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()

for pat in PATTERNS:
    hits = list(re.finditer(re.escape(pat), s))
    print("=" * 18, "%s (%d hits)" % (pat, len(hits)))
    for m in hits[:4]:
        a, b = max(0, m.start() - 600), min(len(s), m.end() + 600)
        print("@%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
        print()
