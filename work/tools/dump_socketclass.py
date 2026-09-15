#!/usr/bin/env python3
"""Dump core.Socket + SocketState (the transport seam for Route B)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

marker = '__reflect(i.prototype,"core.Socket")'
i = d.find(marker)
print("marker at", i)
j = d.rfind("var core;", 0, i)
seg = d[j:i + 80]
open(str(PROJECT_ROOT) + "/work/socketclass.txt", "w", encoding="utf8").write(re.sub(r"([;{}])", r"\1\n", seg))
print("socket class chars:", len(seg))

print("\n=== SocketState enum ===")
for m in re.finditer(r"SocketState", d):
    h = m.start()
    ctx = d[max(0, h - 320):h + 260]
    if "Empty" in ctx:
        print(ctx.replace("\n", " "))
        break

print("\n=== SocketEventType enum ===")
k = d.find("SocketEventType=")
print(d[k:k + 420] if k >= 0 else "?")
