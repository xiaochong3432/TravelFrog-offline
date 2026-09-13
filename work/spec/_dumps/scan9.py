#!/usr/bin/env python3
import re
d = open(r"H:\AI\frog\work\base\assets\game\js\main.min.js", "rb").read().decode("utf8", "replace")
for k in ["formatPath", "formatPathImage", "path=", "PathManage"]:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s (%d) %s" % (k, len(hits), hits[:6]))
i = d.index("e.path=") if "e.path=" in d else -1
print("path ns at", i)
for m in re.finditer(r"function\s+t\s*\(e\)\s*\{\s*return\s*[^}]{0,200}_png", d):
    print("@%d %s" % (m.start(), m.group(0)))
