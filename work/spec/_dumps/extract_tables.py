#!/usr/bin/env python3
"""Extract all JSON tables from config.eab into work/spec/_dumps/tables/."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eabdec

SRC = r"H:\AI\frog\work\run\web\resource\China\eab\config.eab"
OUT = r"H:\AI\frog\work\spec\_dumps\tables"
os.makedirs(OUT, exist_ok=True)

plain, index, off = eabdec.decode(SRC)
pos = off
for e in index:
    s = e.get("s", 0)
    blob = plain[pos:pos + s]
    pos += s
    name = e["n"].replace("_json", "") + ".json"
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(blob)
print("extracted %d tables -> %s" % (len(index), OUT))
