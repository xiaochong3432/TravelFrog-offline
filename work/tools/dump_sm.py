#!/usr/bin/env python3
"""Locate and dump core.SocketManage by its __reflect registration."""
import re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

m = re.search(r'e\.SocketManage\s*=\s*t\s*,\s*__reflect\(\s*t\.prototype\s*,\s*"core\.SocketManage"', d)
print("match:", bool(m))
if m:
    end = m.end()
    start = d.rfind("var core;", 0, m.start())
    body = d[start:end + 200]
    open(r"H:\AI\frog\work\socketmanage.txt", "w", encoding="utf8").write(body)
    print(f"block {start}..{end}  ({len(body)} chars) -> work/socketmanage.txt")
