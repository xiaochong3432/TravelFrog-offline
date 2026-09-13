#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Per-species tab spread, plus the tab labels from the client's own skin."""
import io
import json
import os
import re
import zipfile

ROOT = r"H:\AI\frog"
GD = json.load(open(ROOT + r"\work\run\engine\data\gamedata.json", encoding="utf-8"))
LST = GD["tables"]["encyclopedia"]["list"]

out = io.open(ROOT + r"\work\logs\ency_species.txt", "w", encoding="utf-8")

by = {}
for k, row in LST.items():
    by.setdefault(row["id"], []).append((int(k), row))

out.write("species: %d\n\n" % len(by))
for sid in sorted(by):
    rows = sorted(by[sid])
    variants = {}
    for long_id, row in rows:
        variants.setdefault(row["sub_id"], {"name": row["sub_name"], "tab": row["tab"],
                                            "min": long_id, "n": 0})
        variants[row["sub_id"]]["n"] += 1
    tabs = sorted({v["tab"] for v in variants.values()})
    out.write("%s %-10s rows=%-3d variants=%-3d tabs=%r\n"
              % (sid, rows[0][1]["name"], len(rows), len(variants), tabs))
    for sub in sorted(variants):
        v = variants[sub]
        out.write("    sub_id=%-3d tab=%-2d pics=%-2d %s\n"
                  % (sub, v["tab"], v["n"], v["name"]))

# ---- the tab labels live in the client skin
out.write("\n--- EncySkin.exml lookup\n")
found = []
for base in (os.path.join(ROOT, "work"),):
    for dp, dn, fn in os.walk(base):
        for f in fn:
            if f.lower() == 'encyskin.exml'.lower():
                found.append(os.path.join(dp, f))
out.write("found files: %r\n" % found)

# also look inside config.eab via the eab tool if the skin is not loose
if not found:
    out.write("no loose EncySkin.exml; checking eab payloads for tab labels\n")
    for dp, dn, fn in os.walk(os.path.join(ROOT, "work", "run", "web")):
        for f in fn:
            if f.endswith('.eab'):
                p = os.path.join(dp, f)
                try:
                    raw = io.open(p, 'rb').read()
                except Exception:
                    continue
                for needle in (b'EncySkin', b'Ency/EncySkin'):
                    i = raw.find(needle)
                    if i >= 0:
                        out.write("  %s contains %r @%d\n" % (f, needle, i))
                        seg = raw[max(0, i - 200):i + 2000].decode('utf-8', 'replace')
                        out.write("    ...%s...\n" % seg.replace('\n', ' ')[:1800])
out.close()
print("wrote logs/ency_species.txt")
