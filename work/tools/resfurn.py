#!/usr/bin/env python3
"""List default.res.json entries whose key/url mentions one of the given words."""
import json, re, sys

p = r"H:\AI\frog\work\base\assets\game\resource\China\default.res.json"
d = open(p, encoding="utf8", errors="replace").read()
j = json.loads(d)
words = sys.argv[1:] or ["furniture", "flowerpot", "compost", "pocket", "tumbler", "bench", "decoration"]
for res in j.get("resources", []):
    s = json.dumps(res, ensure_ascii=False)
    if any(w.lower() in s.lower() for w in words):
        print(s)
