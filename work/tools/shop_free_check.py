#!/usr/bin/env python3
"""Look for genuinely free entries in the shop tables.

ShopView.buy branches on `is_free` in the item_buy reply to show ShopAdsView
(skin ShopAdsSkin, whose button art is 「分享拿福利」). Two candidates for "free":
  * rows with price 0            -- free as data, not as a promotion
  * rows with a `free`/`is_free` style column
The live service also handed out random 免单 promotions, which cannot be
recovered; this script tells us whether anything free is written in the data
before we consider inventing a rule.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
import os
import sys

DATA = str(PROJECT_ROOT) + "/work/run/engine/data/gamedata.json"

with open(DATA, encoding="utf-8") as fh:
    d = json.load(fh)
tables = d["tables"]

for name in ("shopData", "Shop", "furnitureShopData", "recharge"):
    t = tables.get(name)
    if t is None:
        continue
    rows = t
    if isinstance(rows, dict) and "list" in rows and isinstance(rows["list"], list):
        rows = rows["list"]
    print("=== %s (%s, %d entries)" % (name, type(rows).__name__, len(rows)))
    if isinstance(rows, dict):
        it = rows.items()
    else:
        it = enumerate(rows)
    cols = {}
    zero = []
    for k, r in it:
        if not isinstance(r, dict):
            continue
        for c in r:
            cols[c] = cols.get(c, 0) + 1
        if "price" in r and str(r.get("price")) in ("0", "0.0"):
            zero.append((k, r))
    print("   columns:", sorted(cols))
    print("   rows with price == 0:", len(zero))
    for k, r in zero[:10]:
        print("     %s %s" % (k, json.dumps(r, ensure_ascii=False)))
    if name == "shopData" and isinstance(rows, dict):
        sample = list(rows.items())[:2]
        for k, r in sample:
            print("   sample %s -> %s" % (k, json.dumps(r, ensure_ascii=False)))
    print()
