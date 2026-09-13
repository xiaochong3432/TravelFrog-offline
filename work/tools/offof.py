#!/usr/bin/env python3
"""Print offsets of a list of literal substrings in main.min.js (char offsets)."""
import sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for line in open(sys.argv[1], encoding="utf8"):
    p = line.rstrip("\n")
    if not p:
        continue
    hits, i = [], d.find(p)
    while i >= 0 and len(hits) < 6:
        hits.append(i)
        i = d.find(p, i + 1)
    print("%-52s %s" % (p[:50], hits))
