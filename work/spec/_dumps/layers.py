#!/usr/bin/env python3
import re, json
JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for k in ["layers"]:
    for m in re.finditer(re.escape(k), d):
        h = m.start()
        print("@%d  %s" % (h, d[max(0, h - 220):h + 220].replace("\n", " ")))
        print("-" * 100)
