#!/usr/bin/env python3
"""How are 百科 (encyclopedia) entries unlocked, and can more real paths feed them?

The engine only unlocks from `state.flowerpot.grown`. Check what the tables offer:
  * encyclopedia  -- the species/variety structure and its desc lines
  * flowerData    -- the plant rows (what the pot grows, what the shop sells)
  * decoration    -- the flowers the frog brings home from a trip
If a brought-home flower maps to an encyclopedia species, travel should unlock it too --
otherwise the 百科 stays "未收集" for a player who only travels.
"""
import io
import json
import os
import sys

ROOT = r"H:\AI\frog\work"
GD = json.load(open(os.path.join(ROOT, "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


def rows_of(v):
    if isinstance(v, dict):
        return v
    if isinstance(v, list):
        return {str(i): r for i, r in enumerate(v)}
    return {}


for name in ["encyclopedia", "flowerData", "decoration"]:
    v = T.get(name)
    say("=" * 70)
    say("=== %s  (%s)" % (name, type(v).__name__))
    if isinstance(v, dict):
        for k, row in list(v.items())[:8]:
            say("  [%s] %s" % (k, json.dumps(row, ensure_ascii=False)[:300]))
    elif isinstance(v, list):
        say("  list n=%d" % len(v))
        for row in v[:6]:
            say("  %s" % json.dumps(row, ensure_ascii=False)[:300])
    say()

# what the pot can grow: the shop's seed items (type 15 sub 2 = 种子/种球)
say("=== seed items (type 15, sub_type 2) with their names ===")
for it in GD["items"]:
    if it.get("type") == 15 and it.get("sub_type") == 2:
        say("  %-8s %s" % (it["id"], it.get("name")))

io.open(os.path.join(ROOT, "logs", "ency_sources.txt"), "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/ency_sources.txt")
