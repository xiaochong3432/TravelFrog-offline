#!/usr/bin/env python3
"""Dump a DECODED-STRING range of main.min.js (offsets match occur.py / dump_class.py)."""
import sys, re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

start = int(sys.argv[1]); end = int(sys.argv[2]); out = sys.argv[3]
seg = d[start:end]
seg = re.sub(r'([;{}])', r'\1\n', seg)
open(out, "w", encoding="utf8").write(seg)
print("chars %d..%d -> %s (%d chars)" % (start, end, out, len(seg)))
