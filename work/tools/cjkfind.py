#!/usr/bin/env python3
"""Search main.min.js for CJK strings WITHOUT passing them through a shell.

`python tools/jsfind.py 与你同行` is mangled by PowerShell's code page (the pattern
arrives as GBK). Reading the patterns from this file avoids the shell entirely.
"""
import os
import re

JS = r"H:\AI\frog\work\run\web\js\main.min.js"
PATTERNS = [
    "与你同行",
    "旅行日记",
    "这一年",
    "年度总结",
]

with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()

for pat in PATTERNS:
    hits = list(re.finditer(re.escape(pat), s))
    print("=" * 18, "%s (%d hits)" % (pat, len(hits)))
    for m in hits[:4]:
        a, b = max(0, m.start() - 600), min(len(s), m.end() + 600)
        print("@%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
        print()
