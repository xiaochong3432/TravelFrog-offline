#!/usr/bin/env python3
"""Dump the craft (手工拼装 / pray) tables and the client's call sites.

Usage: python tools/pray_spec.py
Writes logs/pray_spec.txt
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
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


T = GD.get("tables", {})
for name in ["prayData", "prayBodyData", "prayNoteData", "stampData", "drawingPageData",
             "drawingCollectData", "drawingCommonData"]:
    v = T.get(name)
    say("=== %s  type=%s" % (name, type(v).__name__))
    if isinstance(v, dict):
        say("    rows=%d keys=%s" % (len(v), sorted(v.keys(), key=lambda x: (len(x), x))[:8]))
        for k in sorted(v.keys(), key=lambda x: (len(x), x))[:2]:
            say("    [%s] %s" % (k, json.dumps(v[k], ensure_ascii=False)[:400]))
    elif isinstance(v, list):
        say("    n=%d" % len(v))
        for row in v[:2]:
            say("    %s" % json.dumps(row, ensure_ascii=False)[:400])
    say()

# define.json bits the craft system uses
DEF = json.load(open(os.path.join(ROOT, "run", "engine", "data", "define.json"),
                     encoding="utf-8"))
say("define scalars of interest:")
for k, v in (DEF.get("scalars") or {}).items():
    if "Compose" in k or "compose" in k or "Pray" in k or "pray" in k or "Stamp" in k:
        say("    %s = %s" % (k, v))
say()

# Who calls req_compose / what id is passed?
say("=== client call sites ===")
for pat in ["req_compose(", "confirm_make_box(", "pray_load_grays", "getBoxCraft(",
            "ItemType.COMPOSE", "COMPOSE"]:
    hits = [m.start() for m in re.finditer(re.escape(pat), CLIENT)]
    say("--- %s : %d hits" % (pat, len(hits)))
    for i in hits[:3]:
        say("   @%d ...%s..." % (i, CLIENT[max(0, i - 420):i + 420].replace("\n", " ")))
    say()

sys.stdout = io.open(os.path.join(ROOT, "logs", "pray_spec.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/pray_spec.txt (%d chars)" % len(out.getvalue()))
