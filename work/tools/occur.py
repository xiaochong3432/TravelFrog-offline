#!/usr/bin/env python3
"""Show every occurrence of a bare identifier in main.min.js with context."""
import re, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

for name in sys.argv[1:]:
    print(f"\n===== {name} =====")
    hits = [m.start() for m in re.finditer(r'\b' + re.escape(name) + r'\b', d)]
    print(f"  {len(hits)} occurrence(s)")
    for off in hits[:10]:
        seg = d[max(0, off - 260):off + 200].replace("\n", " ")
        print(f"  [{off}] ...{seg}...")
