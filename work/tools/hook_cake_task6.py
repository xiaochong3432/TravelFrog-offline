#!/usr/bin/env python3
"""Insert the partycake task-6 hook into departFrog (ASCII anchors only, because the
surrounding lines are Chinese comments that the Windows console mangles)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

P = str(PROJECT_ROOT) + "/work/run/engine/index.js"
src = io.open(P, encoding="utf-8").read()

anchor = "cookingTaskProgress(5, 1);"
assert src.count(anchor) == 1, "expected exactly one cookingTaskProgress(5, 1)"
i = src.index(anchor) + len(anchor)
add = ("\n    /* 生日蛋糕 task 6 \"聚会或是旅行\" -- an internal departure, so the same"
       " reason as above. */\n    pcTaskProgress(6, 1);")
src = src[:i] + add + src[i:]
io.open(P, "w", encoding="utf-8").write(src)
print("inserted pcTaskProgress(6, 1) after cookingTaskProgress(5, 1)")
print("pcTaskProgress call sites:", src.count("pcTaskProgress("))
