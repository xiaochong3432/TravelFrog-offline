#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Inspect the encyclopedia table the client indexes, and what our engine sends."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import re

ROOT = str(PROJECT_ROOT)
GD = json.load(open(ROOT + r"\work\run\engine\data\gamedata.json", encoding="utf-8"))
T = GD["tables"]

out = io.open(ROOT + r"\work\logs\ency_table.txt", "w", encoding="utf-8")

enc = None
for name in T:
    if "ency" in name.lower():
        out.write("table %r: %d keys\n" % (name, len(T[name])))
        enc = T[name]

if enc:
    out.write("table top-level keys: %r\n" % list(enc.keys()))
    lst = enc.get("list") or {}
    keys = list(lst.keys())
    out.write("list: %d rows; first 8 keys %r\n" % (len(keys), keys[:8]))
    for k in keys[:4]:
        out.write("  %s -> %s\n" % (k, json.dumps(lst[k], ensure_ascii=False)))
    # field census
    fields = {}
    for k, row in lst.items():
        for f in row:
            fields[f] = fields.get(f, 0) + 1
    out.write("fields across rows: %r\n" % fields)
    out.write("desc: %d keys; sample %r\n" % (len(enc.get("desc") or {}),
                                               list((enc.get("desc") or {}).items())[:2]))
    # how many distinct species (rows sharing `id`) and which keys belong to species 1
    ids = {}
    for k, row in lst.items():
        ids.setdefault(str(row.get("id")), []).append(k)
    out.write("distinct ids: %d\n" % len(ids))
    for sid in list(ids.keys())[:5]:
        out.write("  id %s -> keys %r\n" % (sid, ids[sid][:6]))
    # does the row's sub_id ever equal its key?
    same = sum(1 for k, row in lst.items() if str(row.get("sub_id")) == str(k))
    out.write("rows whose sub_id == key: %d / %d\n" % (same, len(lst)))

# what the engine considers the rows
eng = io.open(ROOT + r"\work\run\engine\index.js", encoding="utf-8").read()
for pat in ["const ENC =", "const ENC_ROWS", "const ENC_DESC"]:
    i = eng.find(pat)
    if i >= 0:
        out.write("\n--- engine %s\n%s\n" % (pat, eng[i:i + 400]))
out.close()
print("wrote logs/ency_table.txt")
