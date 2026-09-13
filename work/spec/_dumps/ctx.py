#!/usr/bin/env python3
import re, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

for k in sys.argv[1:]:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s  (%d)" % (k, len(hits)))
    for h in hits[:25]:
        print("   [%d] ...%s..." % (h, d[max(0, h-160):h+160].replace("\n", " ")))
