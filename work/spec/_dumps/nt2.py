#!/usr/bin/env python3
"""Summarise the note / picture / collection tables (UTF-8 safe output)."""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import json, io, sys, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
B = str(PROJECT_ROOT) + "/work/spec/_dumps/tables/%s.json"


def load(n):
    return json.load(open(B % n, encoding="utf8"))


note = load("Note")
sup = {int(k): v for k, v in (load("Specialty") and {}).items()} if False else None

print("### Note: type=2 examples")
for k, v in sorted(note.items(), key=lambda x: int(x[0])):
    if v.get("type") == 2:
        print(" ", k, json.dumps(v, ensure_ascii=False)[:500])
print()
print("### Note: Own_Note (no type) examples")
n = 0
for k, v in sorted(note.items(), key=lambda x: int(x[0])):
    if v.get("factorType") == "Own_Note":
        print(" ", k, json.dumps(v, ensure_ascii=False)[:500])
        n += 1
        if n >= 6:
            break
print()
ids = sorted(int(k) for k in note)
print("Note id range:", ids[0], "..", ids[-1])
print("Note ids of Own_Note:", sorted(int(k) for k, v in note.items() if v.get("factorType") == "Own_Note"))
print("Note ids with attach:", sorted(int(k) for k, v in note.items() if "attach" in v)[:40])
print()
pic = load("Picture")
keys = collections.Counter()
for v in pic:
    for kk in v:
        keys[kk] += 1
print("### Picture keys:", dict(keys))
print("Picture ids:", sorted(v["id"] for v in pic)[:20], "...", sorted(v["id"] for v in pic)[-5:], "count", len(pic))
print()
print(json.dumps(pic[0], ensure_ascii=False, indent=1)[:2000])
