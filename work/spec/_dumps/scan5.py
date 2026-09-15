#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re
JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for k in ["ItemType.LunchBox", "ItemType.Amulet", "ItemType.Tools", "ItemType.Specialty",
          "getBagDataList", "getDeskDataList", "hasBagItem", "hasDeskItem",
          "item_putin_bag", "item_putin_desk", "item_takeout_bag", "item_takeout_desk",
          "bag_completed", "bag_conflict", "desk_conflict"]:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s (%d) %s" % (k, len(hits), hits[:14]))
    for h in hits[:4]:
        print("     %s" % d[max(0, h - 120):h + 120])
