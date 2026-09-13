#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re
d = open(str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js", "rb").read().decode("utf8", "replace")
for k in ["formatPath", "formatPathImage", "path=", "PathManage"]:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s (%d) %s" % (k, len(hits), hits[:6]))
i = d.index("e.path=") if "e.path=" in d else -1
print("path ns at", i)
for m in re.finditer(r"function\s+t\s*\(e\)\s*\{\s*return\s*[^}]{0,200}_png", d):
    print("@%d %s" % (m.start(), m.group(0)))
