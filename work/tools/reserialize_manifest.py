#!/usr/bin/env python3
"""Re-serialize the merged resource manifest in the ORIGINAL byte format.

The retail `default.res.json` is a single-line compact JSON document:
    {"groups":[...],"resources":[...]}
Merging with json.dump(indent=2) rewrote 469 KB as 652 KB of whitespace -- functionally
fine, but it makes every future diff unreadable and changes a file we do not need to
change more than necessary.

This tool (1) proves our serializer reproduces the ORIGINAL bytes exactly, then
(2) rewrites the merged manifest the same way.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
import os
import sys

ROOT = str(PROJECT_ROOT)
BACKUP = os.path.join(ROOT, "work", "merge-backup", "20260912-202751",
                      "resource", "China", "default.res.json")
MERGED = os.path.join(ROOT, "work", "run", "web", "resource", "China", "default.res.json")

original = open(BACKUP, "rb").read()
data = json.loads(original.decode("utf-8"))

candidates = {
    "compact/ensure_ascii=False": lambda o: json.dumps(o, ensure_ascii=False, separators=(",", ":")),
    "compact/ensure_ascii=True": lambda o: json.dumps(o, ensure_ascii=True, separators=(",", ":")),
}
proven = None
for label, fn in candidates.items():
    out = fn(data).encode("utf-8")
    print(f"  {label:28} -> {len(out)} bytes  identical={out == original}")
    if out == original and proven is None:
        proven = (label, fn)
if not proven:
    print("could not reproduce the original bytes with either serializer -- NOT rewriting")
    sys.exit(1)
print(f"serializer proven: {proven[0]}")

merged = json.loads(open(MERGED, "rb").read().decode("utf-8"))
before = len(open(MERGED, "rb").read())
payload = proven[1](merged).encode("utf-8")
open(MERGED, "wb").write(payload)
print(f"merged manifest rewritten: {before} -> {len(payload)} bytes")

# semantic check: merged differs from the original only by the intended additions
orig = {r["name"]: r for r in data["resources"]}
new = {r["name"]: r for r in merged["resources"]}
added = sorted(set(new) - set(orig))
removed = sorted(set(orig) - set(new))
changed = [k for k in orig if k in new and json.dumps(orig[k], sort_keys=True) != json.dumps(new[k], sort_keys=True)]
print(f"entries added={len(added)} removed={len(removed)} changed={len(changed)}")
print(f"  changed names: {changed}")
assert not removed, "the manifest lost entries"
print("OK")
