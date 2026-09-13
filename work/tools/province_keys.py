#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""What exactly does the engine put into acquireProvinces, and what does the client
expect there? Dumps the visitors.provinceList keys/rows and the client's city parsing."""
import io
import json
import re

ROOT = r"H:\AI\frog"
GD = json.load(open(ROOT + r"\work\run\engine\data\gamedata.json", encoding="utf-8"))
PL = GD["tables"]["visitors"]["provinceList"]

out = io.open(ROOT + r"\work\logs\province_keys.txt", "w", encoding="utf-8")
out.write("provinceList: %d keys\n" % len(PL))
keys = list(PL.keys())
out.write("keys[:37] = %r\n" % keys[:37])
out.write("key type sample: %r\n" % [type(k).__name__ for k in keys[:5]])
out.write("\nfirst 3 rows:\n")
for k in keys[:3]:
    out.write("  %r -> %s\n" % (k, json.dumps(PL[k], ensure_ascii=False)))

# the engine's own visitor construction
eng = io.open(ROOT + r"\work\run\engine\index.js", encoding="utf-8").read()
i = eng.find("function pickVisitor()")
out.write("\n--- engine pickVisitor (@%d)\n%s\n" % (i, eng[i:i + 1600]))

# the client: how it turns `city` into a province
cli = io.open(ROOT + r"\work\run\web\js\main.min.js", encoding="utf-8", errors="replace").read()
for m in re.finditer(r".{300}city\.split\(.{300}", cli):
    out.write("\n--- client city.split @%d\n%s\n" % (m.start(), m.group(0)))
for m in re.finditer(r".{200}acquire.{300}", cli):
    out.write("\n--- client acquire @%d\n%s\n" % (m.start(), m.group(0)))
out.close()
print("wrote logs/province_keys.txt")
