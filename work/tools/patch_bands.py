#!/usr/bin/env python3
"""Group the CDN's file list by patch band.

patch.json entries look like
    "js/main.min.js": {"0": "1020_1021", "1": "<md5>", "2": 711053}
where [0] is the patch band the file changed in. The newest band is newer than our
APK (1.0.20), so its file list is exactly what a 1.0.21 update would add -- and that
is where any content our snapshot lacks would come from.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import collections
import io
import json
import os
import re
import sys

ROOT = str(PROJECT_ROOT)
CDN = os.path.join(ROOT, "work", "cdn")
j = json.load(open(os.path.join(CDN, "patch.json"), encoding="utf-8"))
files = {k: v for k, v in j.items() if not k.startswith("__")}

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


bands = collections.Counter(v.get("0", "?") for v in files.values())
say("=== files per patch band ===")
for b, n in sorted(bands.items()):
    say("  %-14s %4d" % (b, n))

say()
say("=== the newest band's files ===")
newest = sorted(bands, key=lambda b: max(int(x) for x in re.findall(r"\d+", b) or [0]))[-1]
say("  newest band: %s" % newest)
sizes = 0
for k, v in sorted(files.items()):
    if v.get("0") == newest:
        sizes += int(v.get("2") or 0)
        say("     %-64s %10s" % (k, v.get("2")))
say("  total %d files, %.1f MB" % (sum(1 for v in files.values() if v.get("0") == newest),
                                   sizes / 1048576))

say()
say("=== every band, by top-level directory ===")
by_dir = collections.defaultdict(collections.Counter)
for k, v in files.items():
    top = k.split("/")[0] if "/" in k else "(root)"
    sub = "/".join(k.split("/")[:2]) if k.count("/") >= 1 else top
    by_dir[v.get("0", "?")][sub] += 1
for b in sorted(by_dir):
    say("  %-14s %s" % (b, ", ".join("%s:%d" % (s, n) for s, n in by_dir[b].most_common(6))))

say()
say("=== does any band list event content by name? ===")
for kw in ["koto", "museum", "Museum", "spring", "greet", "party", "capsule", "scene", "eab"]:
    hit = [k for k in files if kw.lower() in k.lower()]
    say("  %-10s %3d  %s" % (kw, len(hit), ", ".join(hit[:3])))

say()
say("=== the biggest files the CDN lists ===")
big = sorted(files.items(), key=lambda kv: -int(kv[1].get("2") or 0))[:15]
for k, v in big:
    say("  %-64s %10s  %s" % (k, v.get("2"), v.get("0")))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "patch_bands.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/patch_bands.txt")
