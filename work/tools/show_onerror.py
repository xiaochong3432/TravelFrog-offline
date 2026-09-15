#!/usr/bin/env python3
"""Print the full window.onerror block(s) from the client log."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

P = str(PROJECT_ROOT) + "/work/run/logs/client.log"
txt = open(P, encoding="utf8", errors="replace").read()

idx = [m.start() for m in re.finditer(r"\[window\.onerror\]", txt)]
print(f"onerror entries: {len(idx)}")
for i, off in enumerate(idx[:3]):
    seg = txt[off:off + 2000]
    print(f"\n{'='*80}\nentry {i+1}\n{'='*80}")
    print(seg)
