#!/usr/bin/env python3
"""Inspect default.res.json: list resource groups (used by loadGroups)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, collections, sys

P = str(PROJECT_ROOT) + "/work/run/web/resource/China/default.res.json"
d = json.load(open(P, encoding="utf8"))
print("top-level keys:", list(d.keys()))
res = d.get("resources", [])
print("resources:", len(res))
groups = d.get("groups", [])
print("groups:", len(groups))
for g in groups:
    keys = g.get("keys", "")
    n = len(keys.split(",")) if keys else 0
    print(f"  {g.get('name'):<16} keys={n}")
print("\nseason-ish resource names:")
names = [r.get("name") for r in res]
sea = sorted({n for n in names if n and "season" in n})
print(f"  {len(sea)} names, sample: {sea[:12]}")
print("\nresource names starting mainout_season:")
mo = sorted({n for n in names if n and n.startswith("mainout_season")})
print(f"  {len(mo)}: {mo[:20]}")
