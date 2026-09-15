#!/usr/bin/env python3
"""Three more checks the version log demands:

  1.0.10  材料制作家具 (the craft flow: pray_* / HandCraftModel)
  1.0.12  个人中心 + 旅行地图留言 (ranking / rank_*)
  1.0.18  新居家行为 (FrogMotionName coverage in our engine)
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

ROOT = str(PROJECT_ROOT)
WEB = os.path.join(ROOT, "work", "run", "web")
JS = os.path.join(WEB, "js", "main.min.js")
ENGINE = io.open(os.path.join(ROOT, "work", "run", "engine", "index.js"),
                 encoding="utf-8").read()
GD = json.load(open(os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


s = io.open(JS, encoding="utf-8", errors="replace").read()

say("=== 1.0.10 材料制作家具: the client's craft commands ===")
for cmd in ["pray_load", "pray_compose", "pray_confirm_make_box", "item_load_handbook",
            "handcraft", "HandCraft"]:
    n = len(re.findall(re.escape(cmd), s))
    say("  client  %-24s %d" % (cmd, n))
say("  engine handlers:")
for m in re.finditer(r"^\s{4}(pray_[a-z_]+|handcraft[a-z_]*)\s*:", ENGINE, re.M):
    say("     " + m.group(1))

say()
say("=== what the craft view actually asks for (send(...) inside HandCraftModel) ===")
for m in list(re.finditer(r"HandCraftModel", s))[:2]:
    a = m.start()
    seg = s[a:a + 3000]
    for sm in re.finditer(r'send\("([a-z_]+)"', seg):
        say("   %s" % sm.group(1))

say()
say("=== 1.0.12 个人中心 / 留言: ranking commands ===")
for cmd in ["rank_load", "rank_like", "rank_get_intro", "RankingController", "RankingView"]:
    n = len(re.findall(re.escape(cmd), s))
    say("  client  %-20s %d" % (cmd, n))
for m in re.finditer(r"^\s{4}(rank_[a-z_]+)\s*:", ENGINE, re.M):
    say("  engine  %s" % m.group(1))
i = ENGINE.find("rank_load:")
say("  engine rank_load body:")
say("    " + ENGINE[i:i + 420].replace("\n", "\n    "))

say()
say("=== 1.0.18 居家行为: FrogMotionName values vs our engine ===")
defn = json.load(open(os.path.join(ROOT, "work", "run", "engine", "data", "define.json"),
                     encoding="utf-8"))
maps = defn.get("maps", {})
cand = {k: v for k, v in maps.items() if re.search(r"motion", k, re.I)}
say("  define.json motion-ish maps: %s" % ", ".join("%s(%d)" % (k, len(v) if hasattr(v, "__len__") else 1)
                                                    for k, v in cand.items()))
for k, v in cand.items():
    if isinstance(v, dict):
        say("  %s = %s" % (k, ", ".join(list(v)[:40])))
say("  engine references FrogMotionName: %d" % len(re.findall(r"FrogMotionName", ENGINE)))
for m in list(re.finditer(r"FrogMotionName", ENGINE))[:4]:
    a, b = max(0, m.start() - 120), min(len(ENGINE), m.end() + 260)
    say("     ...%s..." % ENGINE[a:b].replace("\n", " "))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "craft_rank_gap.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/craft_rank_gap.txt")
