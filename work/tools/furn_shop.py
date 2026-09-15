#!/usr/bin/env python3
"""Inspect the FurnitureShop table rows that the client treats as WELFARE goods.

FurnitureShopView.openBuyTips branches on `998 == FurnitureShopDB.get(shop_id).type`:
type 998 means "嘟嘟代理福利商品", which is the only path that shows the
FurnitureAdsView popup ("分享拿福利" = share_btn3_png). Print every row whose type
is 998, plus a summary of the types present, straight from the extracted tables.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CANDIDATES = [
    os.path.join(ROOT, "run", "engine", "data", "tables.json"),
    os.path.join(ROOT, "run", "engine", "data", "gamedata.json"),
    os.path.join(ROOT, "run", "web", "resource", "China", "gamedata.json"),
]


def load():
    for p in CANDIDATES:
        if os.path.isfile(p):
            with open(p, encoding="utf-8") as fh:
                return p, json.load(fh)
    # fall back: scan the engine's own data dir
    d = os.path.join(ROOT, "run", "engine", "data")
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith(".json"):
                p = os.path.join(d, f)
                try:
                    with open(p, encoding="utf-8") as fh:
                        j = json.load(fh)
                except Exception:
                    continue
                if isinstance(j, dict) and "FurnitureShop" in j:
                    return p, j
    return None, None


path, data = load()
print("data file:", path)
if not data:
    raise SystemExit("no table file found")

tables = data.get("tables", data)
fs = tables.get("FurnitureShop") or {}
print("FurnitureShop rows:", len(fs))


def as_list(v):
    if isinstance(v, dict):
        return [(k, v[k]) for k in sorted(v, key=lambda x: (len(str(x)), str(x)))]
    if isinstance(v, list):
        return list(enumerate(v))
    return []


types = {}
for k, row in as_list(fs):
    t = row.get("type")
    types[t] = types.get(t, 0) + 1
print("types present:", types)

print("\n--- rows with type 998 (嘟嘟代理福利商品) ---")
n = 0
for k, row in as_list(fs):
    if row.get("type") == 998 or str(row.get("type")) == "998":
        n += 1
        print("  id=%-6s item_id=%-8s price=%-6s limit=%-4s order=%-4s has_item=%s"
              % (row.get("id", k), row.get("item_id"), row.get("price"),
                 row.get("limit"), row.get("order"), row.get("has_item")))
if not n:
    print("  (none)")

print("\n--- first 5 rows of any type, for shape reference ---")
for k, row in as_list(fs)[:5]:
    print("  %s -> %s" % (k, json.dumps(row, ensure_ascii=False)))
