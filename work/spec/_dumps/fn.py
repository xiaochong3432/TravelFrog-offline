#!/usr/bin/env python3
import re, sys
JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
name = sys.argv[1]
pat = r"function\s+" + re.escape(name) + r"\s*\("
hits = [m.start() for m in re.finditer(pat, d)]
print(name, hits)
for h in hits[:6]:
    # brace balance from the body
    i = d.index("{", h)
    depth = 0
    for j in range(i, min(len(d), i + 4000)):
        if d[j] == "{":
            depth += 1
        elif d[j] == "}":
            depth -= 1
            if depth == 0:
                print("---- @%d len=%d" % (h, j - h))
                print(d[h:j + 1])
                break
