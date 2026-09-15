#!/usr/bin/env python3
"""Find which code paths request a given protocol command."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, sys

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

names = sys.argv[1:]
for name in names:
    pat = 'send("' + name
    print(f"\n===== {name} =====")
    hits = [m.start() for m in re.finditer(re.escape(pat), d)]
    print(f"  {len(hits)} call site(s)")
    for off in hits[:6]:
        seg = d[max(0, off - 320):off + 220].replace("\n", " ")
        print(f"  [{off}] ...{seg}...")
