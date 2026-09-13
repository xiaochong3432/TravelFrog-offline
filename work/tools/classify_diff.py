#!/usr/bin/env python3
"""Classify the 101 differing patch entries: JS vs resource manifest vs data vs art."""
import json, os, hashlib, collections

d = json.load(open(r"H:\AI\frog\work\cdn\patch.json", encoding="utf8"))
files = {k: v for k, v in d.items() if not k.startswith("__")}
WEB = r"H:\AI\frog\work\run\web"

diff, missing = [], []
for p, m in files.items():
    local = os.path.join(WEB, p.replace("/", os.sep))
    if not os.path.isfile(local):
        missing.append((p, m))
        continue
    if hashlib.md5(open(local, "rb").read()).hexdigest() != m["1"]:
        diff.append((p, m, os.path.getsize(local)))

print(f"differing: {len(diff)}   cdn-only: {len(missing)}\n")

print("=== all differing files ===")
for p, m, sz in sorted(diff):
    print(f"  {p:<62} local={sz:>9,} cdn={m['2']:>9,}  dir={m['0']}")

print("\n=== is the resource manifest involved? ===")
for key in ["resource/China/default.res.json", "resource/China/default.thm.json",
            "resource/China/default.scale9.json", "version.json", "manifest.json"]:
    state = "NOT IN PATCH"
    if key in files:
        local = os.path.join(WEB, key.replace("/", os.sep))
        if not os.path.isfile(local):
            state = "CDN-ONLY"
        else:
            same = hashlib.md5(open(local, "rb").read()).hexdigest() == files[key]["1"]
            state = "IDENTICAL" if same else "DIFFERS"
    print(f"  {key:<44} {state}")
