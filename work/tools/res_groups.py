#!/usr/bin/env python3
"""Inspect default.res.json: list resource groups (used by loadGroups)."""
import json, collections, sys

P = r"H:\AI\frog\work\run\web\resource\China\default.res.json"
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
