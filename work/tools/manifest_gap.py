#!/usr/bin/env python3
"""Final two questions before writing the comparison up:

  1. Does our resource manifest (version.json) know about the 2025-11 探秘东山岛
     assets at all? If it does, they exist on a CDN and could still be fetched; if
     it does not, that content simply postdates this snapshot.
  2. What does our engine actually serve for the museum catalog (1.0.11) versus the
     compass adventure (2024-08)?
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
ENGINE = io.open(os.path.join(ROOT, "work", "run", "engine", "index.js"),
                 encoding="utf-8").read()
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


vj = json.load(open(os.path.join(WEB, "version.json"), encoding="utf-8"))
say("=== resource manifest (version.json, %d entries) ===" % len(vj))
for kw in ["koto", "dongshan", "东山", "north", "newyear", "2024", "2025", "museum",
           "MuseumDay", "springcard", "greetcard"]:
    hit = [k for k in vj if kw.lower() in k.lower()]
    say("  %-12s %d  %s" % (kw, len(hit), ", ".join(hit[:3])))

say()
say("=== newest-looking entries in the manifest ===")
for k in sorted(vj)[-8:]:
    say("  %s" % k)

say()
say("=== what our engine returns for the museum ===")
for name in ["museum_load:", "museumday_load:", "museumday_info:"]:
    i = ENGINE.find(name)
    if i > 0:
        say("  %s" % ENGINE[i:i + 200].replace("\n", "\n     "))

say()
say("=== the client's museum views (which of them can our data fill?) ===")
JS = os.path.join(WEB, "js", "main.min.js")
s = io.open(JS, encoding="utf-8", errors="replace").read()
for kw in ["MuseumDayView", "MuseumView", "MuseumController", "museum_get",
           "museum_inspire", "compass"]:
    say("  %-18s %d" % (kw, len(re.findall(re.escape(kw), s))))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "manifest_gap.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/manifest_gap.txt")
