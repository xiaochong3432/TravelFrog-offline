#!/usr/bin/env python3
"""Probe the item table for the fields that drive travel.

The food blurbs already hint that items carry a destination/terrain quality
("短途观光的美味餐点" vs "出门远行的最佳选择", "在沙漠享用味道更佳"), so the
encoding is probably sub_type. This dumps the distributions.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import collections
import json
import os

D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
OUT = str(PROJECT_ROOT) + "/work/build/item_probe.txt"

items = json.load(open(os.path.join(D, "Item.json"), encoding="utf-8"))
specialty = json.load(open(os.path.join(D, "Specialty.json"), encoding="utf-8"))
goal = json.load(open(os.path.join(D, "GoalNumber.json"), encoding="utf-8"))
note = json.load(open(os.path.join(D, "Note.json"), encoding="utf-8"))

with open(OUT, "w", encoding="utf-8") as out:
    by_type = collections.defaultdict(list)
    for it in items:
        by_type[it.get("type")].append(it)

    out.write("=== item types ===\n")
    for t in sorted(by_type):
        out.write(f"  type {t}: {len(by_type[t])} items\n")

    out.write("\n=== sub_type values per type ===\n")
    for t in sorted(by_type):
        st = collections.Counter(str(i.get("sub_type")) for i in by_type[t])
        out.write(f"  type {t}: {dict(list(st.items())[:12])}\n")

    out.write("\n=== type 0 (food) sample, all fields ===\n")
    for it in by_type[0][:10]:
        out.write(f"  {json.dumps(it, ensure_ascii=False)}\n")

    out.write("\n=== type 1 (amulet) sample ===\n")
    for it in by_type[1][:8]:
        out.write(f"  {json.dumps(it, ensure_ascii=False)}\n")

    out.write("\n=== type 2 (tools) sample ===\n")
    for it in by_type[2][:8]:
        out.write(f"  {json.dumps(it, ensure_ascii=False)}\n")

    out.write("\n=== Specialty places ===\n")
    pl = collections.Counter(s.get("place") for s in specialty)
    out.write(f"  {dict(pl)}\n")
    out.write(f"  itemId range: {min(s['itemId'] for s in specialty)}..{max(s['itemId'] for s in specialty)}\n")

    out.write("\n=== GoalNumber (38) ===\n")
    for g in goal:
        out.write(f"  {json.dumps(g, ensure_ascii=False)}\n")

    out.write("\n=== Note samples (all fields) ===\n")
    for k in list(note)[:10]:
        out.write(f"  {k}: {json.dumps(note[k], ensure_ascii=False)}\n")
    out.write("\n=== Note factorType / type / quality distributions ===\n")
    out.write(f"  factorType: {dict(collections.Counter(str(v.get('factorType')) for v in note.values()))}\n")
    out.write(f"  type      : {dict(collections.Counter(str(v.get('type')) for v in note.values()))}\n")
    out.write(f"  quality   : {dict(collections.Counter(str(v.get('quality')) for v in note.values()))}\n")
    out.write(f"  factorData: {dict(collections.Counter(str(v.get('factorData')) for v in note.values()))}\n")

print(f"wrote {OUT}")
