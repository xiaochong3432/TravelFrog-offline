#!/usr/bin/env python3
"""Feature-by-feature comparison against the published version history.

For each feature named in the update log, look for the EVIDENCE in the package we
ship: a data table, a client protocol family, an asset, or an engine handler. The
point is to separate three very different situations:

  * the content is in the package AND our engine serves it      -> working
  * the content is in the package but the event window is closed -> present, unreachable
  * the content is not in this client snapshot at all            -> genuinely absent
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

OUT = io.StringIO()


def say(s=""):
    OUT.write(s + "\n")

ROOT = str(PROJECT_ROOT)
WEB = os.path.join(ROOT, "work", "run", "web")
GD = json.load(open(os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
ENGINE = open(os.path.join(ROOT, "work", "run", "engine", "index.js"), encoding="utf-8").read()

TABLES = GD.get("tables", {})
ITEMS = GD.get("items", [])

# flatten every string that appears anywhere in the data tables, once
BLOB = []


def harvest(o, path=""):
    if isinstance(o, dict):
        for k, v in o.items():
            harvest(v, path + "/" + str(k))
    elif isinstance(o, list):
        for v in o:
            harvest(v, path)
    elif isinstance(o, str):
        BLOB.append((o, path))


harvest(TABLES)
harvest(ITEMS)

# The Windows console code page mangles CJK, which is exactly the content of this
# report -- so write it to a UTF-8 file and read that instead of trusting the
# console. (Learned the hard way: every Chinese label came out as mojibake.)
sys.stdout = open(os.path.join(ROOT, "work", "logs", "feature_gap.txt"), "w", encoding="utf-8")
print("strings harvested from the data tables: %d" % len(BLOB))

# assets: file names only (cheap, and enough to see whether art exists)
ASSETS = []
for dp, dn, fn in os.walk(os.path.join(WEB, "resource", "China")):
    for f in fn:
        ASSETS.append(f)

# protocol families our engine does NOT implement
proto_src = open(os.path.join(ROOT, "work", "run", "engine", "protocol.js"), encoding="utf-8").read()
proto = json.loads(proto_src[proto_src.index("{"):proto_src.rindex("}") + 1])
implemented = set(re.findall(r"^    ([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\(", ENGINE, re.M))
missing_cmds = sorted(c for c in proto if c not in implemented)
fam = {}
for c in missing_cmds:
    fam[c.split("_")[0]] = fam.get(c.split("_")[0], 0) + 1
print("unimplemented commands by family:", fam)
print()

QUESTIONS = [
    ("1.0.3", "中国元素家具/食物/道具",
     ["饺子", "香葱包子", "桂花蒸米糕", "葫芦", "玉佩", "水墨纸伞", "屏风", "蒸笼"]),
    ("1.0.10", "伙伴「嘟嘟」+ 材料制作家具",
     ["嘟嘟", "drummer", "材料", "handcraft", "制作"]),
    ("1.0.10", "明信片保存相册 + 全面屏",
     ["album", "相册", "save_new"]),
    ("1.0.11", "博物馆联动（吴文化博物馆）",
     ["博物馆", "museum", "museumData"]),
    ("1.0.11", "庭院流水/叶子动效",
     ["water", "leaf", "mainout_season"]),
    ("1.0.11", "旅行笔记 + 旅友赠礼",
     ["笔记", "note", "赠礼", "gift", "StoryGift"]),
    ("1.0.12", "热带风格家具",
     ["热带", "tropical", "椰子", "棕榈"]),
    ("1.0.12", "旅行地图留言通知 + 个人中心评论",
     ["留言", "评论", "intro", "rank_get_intro", "Ranking"]),
    ("1.0.13", "玩具不倒翁",
     ["不倒翁", "tumbler"]),
    ("1.0.15", "昼夜系统",
     ["HoursType", "day", "evening", "night", "late_night"]),
    ("1.0.16", "四季变迁 + 冬季雪景",
     ["Season", "spring", "summer", "autumn", "winter", "雪"]),
    ("1.0.16", "春节活动：制作春节祝福",
     ["春节", "springcard", "SpringCard", "祝福"]),
    ("1.0.18", "夏季场景 + 萤火虫 + 新居家行为",
     ["萤火虫", "firefly", "照镜子", "西瓜", "打瞌睡", "mirror"]),
    ("2024-08", "四馆联动博物馆冒险",
     ["museumday", "MuseumDay", "冒险", "四馆"]),
    ("2024", "节日彩蛋 / 新家具 / 庭院装饰",
     ["moment", "Moment", "decoration", "furniture"]),
    ("2025-11", "探秘东山岛：南门湾 / 野营流星 / 故事篇章 / 护身符",
     ["东山", "南门湾", "流星", "koto", "Koto", "护身符", "amulet"]),
]

for ver, name, keys in QUESTIONS:
    hits_data, hits_asset, hits_engine = [], [], []
    for k in keys:
        kl = k.lower()
        n = sum(1 for s, p in BLOB if kl in s.lower())
        if n:
            hits_data.append("%s x%d" % (k, n))
        a = sum(1 for f in ASSETS if kl in f.lower())
        if a:
            hits_asset.append("%s x%d" % (k, a))
        e = len(re.findall(re.escape(k), ENGINE, re.I))
        if e:
            hits_engine.append("%s x%d" % (k, e))
    print("%-9s %s" % (ver, name))
    print("            data   : %s" % (", ".join(hits_data[:8]) or "—"))
    print("            assets : %s" % (", ".join(hits_asset[:8]) or "—"))
    print("            engine : %s" % (", ".join(hits_engine[:8]) or "—"))
