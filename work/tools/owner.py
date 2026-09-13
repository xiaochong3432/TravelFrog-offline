#!/usr/bin/env python3
"""Find the class that owns a given offset in main.min.js."""
import re, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
off = int(sys.argv[1])

CLASS = re.compile(r'var\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function')
best = None
for m in CLASS.finditer(d):
    if m.start() <= off:
        best = (m.start(), m.group(1))
    else:
        break
print(f"offset {off} is inside class: {best[1]} (starts at {best[0]})")

# show the nearest enclosing method
seg = d[max(0, off - 100):off + 100]
print("context:", seg.replace("\n", " "))

# print the whole class body (bounded)
end = d.find("__reflect(" + best[1] + ".prototype", off)
if end < 0:
    end = off + 3000
body = d[best[0]:end + 120]
print(f"\nclass body: {len(body)} chars")
for kw in ("center_scroller", "on_resize", "updateSafeTop", "checkGuide"):
    i = body.find(kw)
    if i >= 0:
        print(f"\n--- {kw} ---")
        print(re.sub(r'([;{}])', r'\1\n', body[i - 60:i + 500]))
