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
print("Note entries:", len(note))
keys = collections.Counter()
for k, v in note.items():
    for kk in v:
        keys[kk] += 1
print("Note keys:", dict(keys))
types = collections.Counter(v.get("type") for v in note.values())
print("Note type histogram:", dict(types))
ft = collections.Counter(v.get("factorType") for v in note.values())
print("Note factorType histogram:", dict(ft))
print()
for i, (k, v) in enumerate(sorted(note.items(), key=lambda x: int(x[0]))):
    if i >= 8:
        break
    print(k, json.dumps(v, ensure_ascii=False)[:400])
print()
for t in sorted(set(v.get("type") for v in note.values())):
    ex = [v for v in note.values() if v.get("type") == t][:2]
    print("--- type", t, json.dumps(ex, ensure_ascii=False)[:500])
