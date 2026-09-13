#!/usr/bin/env python3
import re
s = open(r"H:\AI\frog\work\run\engine\protocol.js", encoding="utf8").read()
names = re.findall(r'"([a-z0-9_]+)":\s*\{', s)
print("album_*:", [k for k in names if k.startswith("album")])
print("travel_*:", [k for k in names if k.startswith("travel")])
print("notify_*:", [k for k in names if k.startswith("notify")])
print("total:", len(names))
