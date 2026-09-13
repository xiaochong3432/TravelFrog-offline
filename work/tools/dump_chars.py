#!/usr/bin/env python3
"""Dump a CHARACTER range of main.min.js (offsets match occur.py / where_literal.py).

dump_range.py uses BYTE offsets, which drift from occur.py's char offsets in any
region containing multi-byte CJK. This helper keeps them consistent.

Usage: dump_chars.py <start_char> <end_char> <outfile>
"""
import sys, re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

start = int(sys.argv[1]); end = int(sys.argv[2]); out = sys.argv[3]
seg = d[start:end]
seg = re.sub(r'([;{}])', r'\1\n', seg)
open(out, "w", encoding="utf8").write(seg)
print(f"chars {start}..{end} -> {out} ({len(seg)} chars)")
