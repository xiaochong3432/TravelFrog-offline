#!/usr/bin/env python3
"""Preview the key extracted tables so the data model is visible at a glance."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
import os

D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
OUT = str(PROJECT_ROOT) + "/work/build/tables_preview.txt"

SHOW = [
    ("gameplay", 4), ("origin", 4), ("Note", 3), ("Picture", 3), ("PictureTag", 3),
    ("Shop", 3), ("shopData", 3), ("Specialty", 3), ("Collection", 3), ("Prize", 3),
    ("visitors", 4), ("Character", 4), ("GoalNumber", 3), ("Achieve", 3),
    ("flowerData", 3), ("flowerpotData", 4), ("compostData", 3), ("pocketData", 3),
    ("furnitureShopData", 3), ("furnitureCommon", 3), ("calendarData", 4),
    ("lotteryData", 4), ("taskData", 4), ("step", 3), ("zh-CN", 5), ("Word", 3),
    ("decoration", 3), ("benchData", 3), ("tumblerData", 3), ("drawingPageData", 3),
]

with open(OUT, "w", encoding="utf-8") as out:
    for name, n in SHOW:
        p = os.path.join(D, name + ".json")
        if not os.path.exists(p):
            out.write(f"===== {name}: MISSING\n\n")
            continue
        obj = json.load(open(p, encoding="utf-8"))
        if isinstance(obj, list):
            out.write(f"===== {name}  list[{len(obj)}]\n")
            for e in obj[:n]:
                out.write(f"  {json.dumps(e, ensure_ascii=False)}\n")
        else:
            out.write(f"===== {name}  dict[{len(obj)}] keys={list(obj)[:8]}\n")
            for k in list(obj)[:n]:
                out.write(f"  {k!r}: {json.dumps(obj[k], ensure_ascii=False)[:400]}\n")
        out.write("\n")
print(f"wrote {OUT}")
