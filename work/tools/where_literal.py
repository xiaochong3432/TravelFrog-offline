#!/usr/bin/env python3
"""Show every occurrence of a literal protocol name with context."""
import re, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

for name in sys.argv[1:]:
    print(f"\n===== {name!r} =====")
    hits = [m.start() for m in re.finditer(re.escape('"' + name + '"'), d)]
    print(f"  {len(hits)} occurrences")
    for off in hits[:8]:
        seg = d[max(0, off - 260):off + 160].replace("\n", " ")
        print(f"  [{off}] ...{seg}...")
