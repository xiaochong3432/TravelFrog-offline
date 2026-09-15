#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re, sys
JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
name = sys.argv[1]
pat = r"function\s+" + re.escape(name) + r"\s*\("
hits = [m.start() for m in re.finditer(pat, d)]
print(name, hits)
for h in hits[:6]:
    # brace balance from the body
    i = d.index("{", h)
    depth = 0
    for j in range(i, min(len(d), i + 4000)):
        if d[j] == "{":
            depth += 1
        elif d[j] == "}":
            depth -= 1
            if depth == 0:
                print("---- @%d len=%d" % (h, j - h))
                print(d[h:j + 1])
                break
