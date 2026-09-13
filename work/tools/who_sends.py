#!/usr/bin/env python3
"""Find which code paths request a given protocol command."""
import re, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

names = sys.argv[1:]
for name in names:
    pat = 'send("' + name
    print(f"\n===== {name} =====")
    hits = [m.start() for m in re.finditer(re.escape(pat), d)]
    print(f"  {len(hits)} call site(s)")
    for off in hits[:6]:
        seg = d[max(0, off - 320):off + 220].replace("\n", " ")
        print(f"  [{off}] ...{seg}...")
