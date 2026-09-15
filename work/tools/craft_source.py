#!/usr/bin/env python3
"""Where do the three COMPOSE wood pieces (8501/8502/8503) come from?

If nothing in our offline build can produce them, the compose UI is a dead end.
Check the shop table, the travel-loot paths and the client's own references.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os
import re
import sys

ROOT = str(PROJECT_ROOT) + "/work"
GD = json.load(open(os.path.join(ROOT, "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()
ENGINE = io.open(os.path.join(ROOT, "run", "engine", "index.js"), encoding="utf-8").read()

PIECES = [8501, 8502, 8503, 5502, 5501]
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


def find_ids(obj, ids, path="$", hits=None):
    if hits is None:
        hits = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, (int, float)) and int(v) in ids:
                hits.append("%s.%s = %s" % (path, k, v))
            if isinstance(v, str) and v.isdigit() and int(v) in ids:
                hits.append("%s.%s = %r" % (path, k, v))
            find_ids(v, ids, "%s.%s" % (path, k), hits)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            if isinstance(v, (int, float)) and int(v) in ids:
                hits.append("%s[%d] = %s" % (path, i, v))
            find_ids(v, ids, "%s[%d]" % (path, i), hits)
    return hits


say("=== tables that mention the pieces / recipe ===")
for name, tab in T.items():
    hits = find_ids(tab, set(PIECES))
    if hits:
        say("  %-22s %d hits: %s" % (name, len(hits), hits[:6]))

say()
say("=== shopData rows with those items ===")
shop = T.get("shopData") or []
for row in (shop if isinstance(shop, list) else []):
    if row.get("itemId") in PIECES or row.get("id") in PIECES:
        say("  " + json.dumps(row, ensure_ascii=False))

say()
say("=== how does the engine roll travel rewards? (item filter) ===")
for kw in ["rollTripRewards", "ITEM_TYPE_SPECIALTY", "function rollTravelItems",
           "lootPool", "travelReward"]:
    i = ENGINE.find(kw)
    if i >= 0:
        say("--- %s @%d" % (kw, i))
        say(ENGINE[max(0, i - 200):i + 900].replace("\n", " ")[:1100])
        say()

say("=== client references to the pieces / COMPOSE type ===")
for pat in ["8501", "5502", "ItemType.COMPOSE", "ToolBagView", "HandCraftStuff"]:
    hits = [m.start() for m in re.finditer(re.escape(pat), CLIENT)]
    say("--- %s : %d" % (pat, len(hits)))
    for i in hits[:2]:
        say("   @%d ...%s..." % (i, CLIENT[max(0, i - 350):i + 350].replace("\n", " ")))

sys.stdout = io.open(os.path.join(ROOT, "logs", "craft_source.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/craft_source.txt (%d chars)" % len(out.getvalue()))
