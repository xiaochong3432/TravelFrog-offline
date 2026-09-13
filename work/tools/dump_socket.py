#!/usr/bin/env python3
"""Dump the core SocketManage / ServiceDispatcher implementation (wire format)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

i = d.find("e.SocketManage=t,__reflect")
print("===== SocketManage class =====")
print(d[i - 6000:i + 400])
