#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

# find every string literal that looks like a protocol command name
lits = {}
for m in re.finditer(r'"([a-z][a-z0-9]*(?:_[a-z0-9]+)+)"', d):
    lits.setdefault(m.group(1), []).append(m.start())

for pre in ("album_", "travel_", "notify_", "client_"):
    print("#" * 30, pre)
    for k in sorted(lits):
        if k.startswith(pre):
            print("  %-28s %s" % (k, lits[k][:8]))
