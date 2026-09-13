#!/usr/bin/env python3
"""Find the assembled amulet and the COMPOSE item type.

`pray_compose` is sent with `Define.ComposeId` (5502 = "木制护符·待拼装") by
BoxCraftView, and its reply is read as `item_list`. We need the item that the
three wood pieces (8501/8502/8503, type 16, sub_type 1..3) actually assemble into.
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
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


say("=== every type 5 item (candidate ItemType.COMPOSE) ===")
for it in items:
    if it.get("type") == 5:
        say("  id=%-7s sub=%-3s spend=%-3s name=%s" % (it.get("id"), it.get("sub_type"),
                                                      it.get("spend"), it.get("name")))

say()
say("=== every type 16 item (sub_type 1..3 = the craft material groups) ===")
for it in items:
    if it.get("type") == 16:
        say("  id=%-7s sub=%-3s name=%s  img=%s" % (it.get("id"), it.get("sub_type"),
                                                    it.get("name"), it.get("img")))

say()
say("=== items whose name contains 护符 / 木制 / 拼 ===")
for it in items:
    nm = str(it.get("name", ""))
    if ("护符" in nm) or ("木制" in nm) or ("拼" in nm):
        say("  id=%-7s type=%-3s sub=%-3s name=%s" % (it.get("id"), it.get("type"),
                                                      it.get("sub_type"), nm))

say()
say("=== the client's DataType.ItemType enum ===")
i = CLIENT.find("ItemType=")
for m in re.finditer(r"ItemType\[?[a-z]*\]?=", CLIENT):
    pass
j = CLIENT.find("DataType.ItemType.FURNITURE_TOOL")
say(CLIENT[max(0, j - 2600):j + 400].replace("\n", " ") if j > 0 else "not found")

sys.stdout = io.open(os.path.join(ROOT, "logs", "craft_product.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/craft_product.txt")
