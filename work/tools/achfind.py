#!/usr/bin/env python3
"""Find the achievement UI paths: the list view, the "new title" popup, and who
reads useAchieveID / cur_achieve."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

JS = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()

for pat in [r"getUseAchieveID", r"isAchieveExpire", r"AchieveViewController",
            r"getAchieveInfoList", r"AchieveDB", r"updateAchieveID"]:
    hits = list(re.finditer(pat, s))
    print("=" * 18, pat, "(%d)" % len(hits))
    for m in hits[:4]:
        a, b = max(0, m.start() - 380), min(len(s), m.end() + 260)
        print("  @%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
        print()
