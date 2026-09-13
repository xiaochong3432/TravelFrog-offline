#!/usr/bin/env python3
"""Dump a BYTE range of main.min.js to a UTF-8 file (offsets match jsctx.py)."""
import sys, re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
raw = open(JS, "rb").read()

start = int(sys.argv[1]); end = int(sys.argv[2])
out = sys.argv[3]
seg = raw[start:end].decode("utf8", "replace")
seg = re.sub(r'([;{}])', r'\1\n', seg)
open(out, "w", encoding="utf8").write(seg)
print(f"bytes {start}..{end} -> {out} ({len(seg)} chars)")
