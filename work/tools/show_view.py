#!/usr/bin/env python3
"""Print the [view] / [view-keys] / [res] probe reports from the client log."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, sys

P = str(PROJECT_ROOT) + "/work/run/logs/client.log"
txt = open(P, encoding="utf8", errors="replace").read()
for tag in ("[view]", "[view-keys]", "[res]", "[tree]", "[view-error]", "[tree-error]"):
    i = txt.find(tag)
    if i < 0:
        print(f"--- {tag}: absent")
        continue
    print(f"\n===== {tag} =====")
    print(txt[i:i + 4200])
