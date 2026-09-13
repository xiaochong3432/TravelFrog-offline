#!/usr/bin/env python3
"""Locate and dump core.SocketManage by its __reflect registration."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

m = re.search(r'e\.SocketManage\s*=\s*t\s*,\s*__reflect\(\s*t\.prototype\s*,\s*"core\.SocketManage"', d)
print("match:", bool(m))
if m:
    end = m.end()
    start = d.rfind("var core;", 0, m.start())
    body = d[start:end + 200]
    open(str(PROJECT_ROOT) + "/work/socketmanage.txt", "w", encoding="utf8").write(body)
    print(f"block {start}..{end}  ({len(body)} chars) -> work/socketmanage.txt")
