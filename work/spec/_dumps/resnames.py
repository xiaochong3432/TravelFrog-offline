#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import json
d = json.load(open(str(PROJECT_ROOT) + "/work/run/web/resource/China/default.res.json", encoding="utf8"))
names = {e.get("name") for e in d["resources"]}
for n in ["photo_frame_png", "pic_1000_png", "word_0_png", "collection_1_png", "sky05_png",
          "g_beijing1_png", "goods_4_png", "item_4_png", "picture_loader_png"]:
    print("%-22s %s" % (n, n in names))
# groups
for g in d.get("groups", []):
    if g.get("name") in ("sheet", "preload", "config"):
        print("group", g["name"], str(g.get("keys"))[:200])
