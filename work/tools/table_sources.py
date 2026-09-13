#!/usr/bin/env python3
"""Resolve game data table resources through the client's resource manifest.

`resource/China/default.res.json` is the manifest; data tables (shopData, Item,
Specialty, Collection, Prize, Character, Shop, GiftData, lotteryData) are listed
there with a url. This prints where each one actually lives so the extraction can
be reproduced instead of relying on leftovers.
"""
import json
import os

WEB = r"H:\AI\frog\work\run\web"
MANIFEST = os.path.join(WEB, r"resource\China\default.res.json")
WANT = ["shopData", "Item", "Specialty", "Collection", "Prize", "Character",
        "Shop", "GiftData", "lotteryData", "GamePlayData"]

man = json.load(open(MANIFEST, encoding="utf-8"))
resources = man.get("resources", man if isinstance(man, list) else [])
print(f"manifest resources: {len(resources)}")

out = open(r"H:\AI\frog\work\build\table_sources.txt", "w", encoding="utf-8")
by_name = {}
for r in resources:
    if not isinstance(r, dict):
        continue
    url = r.get("url", "")
    name = r.get("name", "")
    by_name[name] = r

for want in WANT:
    hits = [r for n, r in by_name.items() if n == want or n.endswith("/" + want)]
    if not hits:
        hits = [r for n, r in by_name.items() if want.lower() in n.lower()]
    for r in hits[:4]:
        url = r.get("url", "")
        # a manifest url may be a comma-separated list of sub-resources
        parts = [p.strip() for p in url.split(",")]
        line = f"{r.get('name'):28s} type={r.get('type'):8s} url={parts[0][:110]}"
        print(line)
        out.write(line + "\n")
        if len(parts) > 1:
            out.write(f"    (+{len(parts) - 1} more sub-urls)\n")
out.close()
