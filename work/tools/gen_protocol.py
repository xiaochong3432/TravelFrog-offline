#!/usr/bin/env python3
"""Emit the embedded ProtocolList as a JS module for the offline engine."""
import re, json, os

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

i = d.find("e.protocolList={")
assert i > 0, "ProtocolList not found"
start = d.index("{", i)
# brace-matched scan
depth = 0
for j in range(start, len(d)):
    if d[j] == "{":
        depth += 1
    elif d[j] == "}":
        depth -= 1
        if depth == 0:
            end = j + 1
            break
raw = d[start:end]
print(f"ProtocolList literal: {len(raw)} chars")

ENTRY = re.compile(r'([A-Za-z_][A-Za-z0-9_]{2,40})\s*:\s*\[\[([^\]]*)\]\s*,\s*!(0|1)\s*\]')
table = {}
for m in ENTRY.finditer(raw):
    params = re.findall(r'"([^"]*)"', m.group(2))
    table[m.group(1)] = {"params": params, "needResponse": m.group(3) == "0"}
print(f"parsed {len(table)} commands")

out = r"H:\AI\frog\work\run\engine\protocol.js"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf8") as f:
    f.write("// Auto-generated from assets/game/js/main.min.js ProtocolList\n")
    f.write("// params = argument names; needResponse = client waits for a reply\n")
    f.write("'use strict';\nmodule.exports = ")
    json.dump(table, f, ensure_ascii=False, indent=1, sort_keys=True)
    f.write(";\n")
print(f"wrote {out}")

need = sum(1 for v in table.values() if v["needResponse"])
print(f"needResponse={need}  fireAndForget={len(table)-need}")
