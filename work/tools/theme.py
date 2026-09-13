#!/usr/bin/env python3
"""Inspect the Egret theme file: what skins exist and how they are stored."""
import json, sys

P = r"H:\AI\frog\work\run\web\resource\China\default.thm.json"

raw = open(P, encoding="utf8", errors="replace").read()
print("length:", len(raw))
print("head:", raw[:300].replace("\n", " "))
try:
    d = json.loads(raw)
except Exception as e:
    print("not JSON:", e)
    sys.exit(0)

print("\ntop keys:", list(d.keys()))
for k, v in d.items():
    if isinstance(v, dict):
        print(f"  {k}: dict len={len(v)}")
        for kk in list(v.keys())[:12]:
            print(f"      {kk}")
    elif isinstance(v, list):
        print(f"  {k}: list len={len(v)} sample={str(v[:3])[:200]}")
    else:
        print(f"  {k}: {str(v)[:120]}")
