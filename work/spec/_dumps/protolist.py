#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re
s = open(str(PROJECT_ROOT) + "/work/run/engine/protocol.js", encoding="utf8").read()
names = re.findall(r'"([a-z0-9_]+)":\s*\{', s)
print("album_*:", [k for k in names if k.startswith("album")])
print("travel_*:", [k for k in names if k.startswith("travel")])
print("notify_*:", [k for k in names if k.startswith("notify")])
print("total:", len(names))
