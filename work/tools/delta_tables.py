#!/usr/bin/env python3
"""Diff the 1.0.21 delta tables against the tables our build currently uses.

The delta files are plain JSON (`work/cdn/live/1020_1021/resource/China/data/...`),
while our build reads the SAME tables out of `config.eab` -- the one ENCRYPTED
bundle -- so "merging a table" means overriding it through default.res.json, not
repacking. This script says what would actually change, and what is genuinely new.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os
import sys

ROOT = str(PROJECT_ROOT) + "/work"
GD = json.load(open(os.path.join(ROOT, "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
DELTA = os.path.join(ROOT, "cdn", "live")
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


def find_delta(name):
    for band in os.listdir(DELTA):
        for dp, dn, fn in os.walk(os.path.join(DELTA, band)):
            for f in fn:
                if f == name + ".json":
                    return os.path.join(dp, f)
    return None


def rows_of(v):
    if isinstance(v, dict):
        return v
    if isinstance(v, list):
        return {str(i): r for i, r in enumerate(v)}
    return {}


say("=== 1.0.21 delta: table files present ===")
names = []
for band in sorted(os.listdir(DELTA)):
    for dp, dn, fn in os.walk(os.path.join(DELTA, band)):
        for f in sorted(fn):
            if f.endswith(".json") and "data" in dp.replace("\\", "/"):
                names.append((band, f[:-5], os.path.join(dp, f)))
for band, n, p in names:
    say("  %-10s %-20s %8d" % (band, n, os.path.getsize(p)))

say()
say("=== museumData: ours vs 1.0.21 ===")
mine = rows_of(T.get("museumData"))
p = find_delta("museumData")
if p:
    theirs = rows_of(json.load(open(p, encoding="utf-8")))
    say("  ours rows=%d  1.0.21 rows=%d" % (len(mine), len(theirs)))
    for k in sorted(set(list(mine.keys()) + list(theirs.keys())), key=lambda x: int(x) if str(x).isdigit() else 0):
        a = mine.get(k) or {}
        b = theirs.get(k) or {}
        say("  id=%-3s name: %-16s -> %-16s  switch: %s -> %s  pic_id: %s -> %s"
            % (k, a.get("name"), b.get("name"), a.get("switch"), b.get("switch"),
               a.get("pic_id"), b.get("pic_id")))
        if b and a.get("pic_res") != b.get("pic_res"):
            say("        pic_res: %s  ->  %s" % (a.get("pic_res"), b.get("pic_res")))
        if b and a.get("collection_id") != b.get("collection_id"):
            say("        collection_id: %s -> %s" % (a.get("collection_id"), b.get("collection_id")))
else:
    say("  no museumData.json in the delta")

say()
say("=== do we already have the art those ids point at? ===")
IMG = os.path.join(ROOT, "run", "web", "resource", "China", "images")
present = set()
for dp, dn, fn in os.walk(IMG):
    for f in fn:
        present.add((os.path.basename(dp), f))
theirs = rows_of(json.load(open(find_delta("museumData"), encoding="utf-8"))) if p else {}
for k in sorted(theirs):
    row = theirs[k] or {}
    res = list(row.get("pic_res") or []) + [row.get("ticket") or {}, row.get("info_ticket") or {}]
    for r in res:
        if not isinstance(r, dict) or not r.get("index"):
            continue
        folder = str(r.get("src", "")).split("/")[-1]
        name = str(r["index"]) + ".png"
        say("  %-22s %-14s %s" % (name, folder, "PRESENT" if (folder, name) in present else "missing"))

sys.stdout = io.open(os.path.join(ROOT, "logs", "delta_tables.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/delta_tables.txt")
