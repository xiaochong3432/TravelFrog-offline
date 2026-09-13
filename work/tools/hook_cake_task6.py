#!/usr/bin/env python3
"""Insert the partycake task-6 hook into departFrog (ASCII anchors only, because the
surrounding lines are Chinese comments that the Windows console mangles)."""
import io

P = r"H:\AI\frog\work\run\engine\index.js"
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
