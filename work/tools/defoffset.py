#!/usr/bin/env python3
"""Print exact character offsets of `prototype.<name>=function` definitions."""
import re, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for name in sys.argv[1:]:
    pat = r'prototype\.' + re.escape(name) + r'\s*=\s*function'
    hits = [m.start() for m in re.finditer(pat, d)]
    print(f"{name:26s} {hits}")
