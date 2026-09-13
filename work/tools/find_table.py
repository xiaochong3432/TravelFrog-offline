#!/usr/bin/env python3
"""Ad-hoc: print every main.min.js site that loads a named config table."""
import re, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for name in sys.argv[1:]:
    print(f"\n===== {name} =====")
    for m in re.finditer(re.escape('"%s"' % name), d):
        print("  @%d  %s" % (m.start(), d[max(0, m.start() - 200):m.start() + 140].replace("\n", " ")))
