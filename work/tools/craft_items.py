#!/usr/bin/env python3
"""What are the craft materials, and what does composing produce?

`BoxCraftView` sends `pray_compose` with `Define.ComposeId` (5502) once the player
holds items of ItemDB.sub_type 1, 2 and 3, and the reply is read as `item_list`.
This dumps the COMPOSE-type items and their sub_types, plus item 5502 itself.
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
items = GD.get("items", [])
ENGINE = io.open(os.path.join(ROOT, "run", "engine", "index.js"), encoding="utf-8").read()

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


say("total items: %d" % len(items))
by_type = {}
for it in items:
    by_type.setdefault(it.get("type"), []).append(it)
say("item types: %s" % {k: len(v) for k, v in sorted(by_type.items(), key=lambda kv: kv[0])})

say()
say("=== any item whose name/type smells like crafting ===")
for it in items:
    nm = str(it.get("name", ""))
    if (it.get("sub_type") or 0) > 0 and it.get("type") in (14, 15, 16, 17, 18, 19, 20, 21):
        say("  id=%s type=%s sub_type=%s name=%s" % (it.get("id"), it.get("type"),
                                                     it.get("sub_type"), nm))

say()
say("=== item 5502 (Define.ComposeId) ===")
for it in items:
    if it.get("id") == 5502:
        say("  " + json.dumps(it, ensure_ascii=False)[:500])
say()
say("=== items 5490..5520 ===")
for it in items:
    if 5490 <= (it.get("id") or 0) <= 5520:
        say("  id=%s type=%s sub=%s name=%s" % (it.get("id"), it.get("type"),
                                                it.get("sub_type"), it.get("name")))

say()
say("=== engine's current pray_load_grays / pray handlers ===")
for m in re.finditer(r"pray_[a-z_]+:", ENGINE):
    ln = ENGINE.count("\n", 0, m.start()) + 1
    seg = ENGINE[m.start():m.start() + 700]
    say("--- L%d %s" % (ln, seg.split("\n\n")[0][:600]))

sys.stdout = io.open(os.path.join(ROOT, "logs", "craft_items.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/craft_items.txt")
