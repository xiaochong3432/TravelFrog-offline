#!/usr/bin/env python3
import re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

# find every string literal that looks like a protocol command name
lits = {}
for m in re.finditer(r'"([a-z][a-z0-9]*(?:_[a-z0-9]+)+)"', d):
    lits.setdefault(m.group(1), []).append(m.start())

for pre in ("album_", "travel_", "notify_", "client_"):
    print("#" * 30, pre)
    for k in sorted(lits):
        if k.startswith(pre):
            print("  %-28s %s" % (k, lits[k][:8]))
