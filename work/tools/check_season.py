#!/usr/bin/env python3
"""Check the season group contents and whether the files exist in the web tree."""
import json, os

RES = r"H:\AI\frog\work\run\web\resource\China\default.res.json"
WEB = r"H:\AI\frog\work\run\web"
d = json.load(open(RES, encoding="utf8"))

groups = {g["name"]: g.get("keys", "").split(",") for g in d.get("groups", [])}
byname = {r["name"]: r for r in d.get("resources", [])}

for gname in ("season11", "mainout"):
    keys = groups.get(gname, [])
    print(f"\n=== group {gname}: {len(keys)} keys ===")
    for k in keys:
        r = byname.get(k)
        url = r.get("url") if r else None
        exists = os.path.exists(os.path.join(WEB, url)) if url else False
        print(f"  {k:<42} url={url} exists={exists}")
