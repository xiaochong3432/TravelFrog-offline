#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""How do sub_id / tab / sub_name relate inside encyclopedia.list?
Decides which variant a species should default to in the show_sub payload."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json

ROOT = str(PROJECT_ROOT)
GD = json.load(open(ROOT + r"\work\run\engine\data\gamedata.json", encoding="utf-8"))
LST = GD["tables"]["encyclopedia"]["list"]

out = io.open(ROOT + r"\work\logs\ency_shape.txt", "w", encoding="utf-8")

# tab census overall
tabs = {}
subs = {}
for k, row in LST.items():
    tabs[row.get("tab")] = tabs.get(row.get("tab"), 0) + 1
    subs[row.get("sub_id")] = subs.get(row.get("sub_id"), 0) + 1
out.write("rows: %d\ntab census: %r\nsub_id census: %r\n" % (len(LST), tabs, subs))

# per species: the distinct variants (sub_id, sub_name, tab) and how many picture rows
by_species = {}
for k, row in LST.items():
    by_species.setdefault(row["id"], []).append((int(k), row))

for sid in sorted(by_species)[:4]:
    rows = sorted(by_species[sid])
    out.write("\nspecies %s (%s): %d rows\n" % (sid, rows[0][1]["name"], len(rows)))
    seen = {}
    for long_id, row in rows:
        key = (row["sub_id"], row["sub_name"], row["tab"])
        seen.setdefault(key, []).append(long_id % 100)
    for key, pics in sorted(seen.items()):
        out.write("  sub_id=%-3s tab=%-2s sub_name=%-8s pics=%r\n"
                  % (key[0], key[2], key[1], pics))

# is (sub_id -> tab) a function across the whole table?
pair = {}
for row in LST.values():
    pair.setdefault(row["sub_id"], set()).add(row["tab"])
out.write("\nsub_id -> set(tab): %r\n" % {k: sorted(v) for k, v in sorted(pair.items())})

# distinct sub_names per species
out.write("\ndistinct sub_names per species (first 4):\n")
for sid in sorted(by_species)[:4]:
    names = sorted({r["sub_name"] for _, r in by_species[sid]})
    out.write("  %s: %r\n" % (sid, names))

out.close()
print("wrote logs/ency_shape.txt")
