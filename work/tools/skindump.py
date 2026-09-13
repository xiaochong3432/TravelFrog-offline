#!/usr/bin/env python3
"""Dump one EXML skin's generated code from default.thm.js.

    python tools/skindump.py AdsGiftSkin
"""
import re
import sys

PATH = r"H:\AI\frog\work\run\web\js\default.thm.js"
needle = sys.argv[1]
span = int(sys.argv[2]) if len(sys.argv) > 2 else 4000

with open(PATH, encoding="utf-8", errors="replace") as fh:
    t = fh.read()

m = re.search(r"generateEUI\.paths\['([^']*%s[^']*)'\]" % re.escape(needle), t)
if not m:
    print("no skin path matching %r" % needle)
    raise SystemExit(1)
print("skin path: %s  @%d" % (m.group(1), m.start()))
seg = t[m.start():m.start() + span]
for line in re.finditer(r"t\.source = \"([^\"]+)\"", seg):
    print("   source: %s" % line.group(1))
print("---- raw (first %d chars) ----" % span)
print(seg[:span])
