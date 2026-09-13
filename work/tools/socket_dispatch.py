#!/usr/bin/env python3
"""How does the client dispatch a reply to the Action that sent the command?

Everything about error codes hinges on this: if SocketManage drops the callback
for nonzero `code`, then a nonzero code is a silent no-op and our getErrorInfo
analysis is beside the point; if it always calls back, callbacks like
`function(e){ e && (...grant item...) }` treat ANY object -- including
`{code:-1}` -- as success.
"""
import io
import os
import re
import sys

ROOT = r"H:\AI\frog\work"
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()

out = io.StringIO()
for kw in ["var SocketManage", "SocketManage=function", "onMessage=function",
           "dispatchMessage", "ActionManage", "prototype.send=function"]:
    i = CLIENT.find(kw)
    out.write("=== %s @%d\n" % (kw, i))
    if i >= 0:
        out.write(CLIENT[i:i + 2600].replace("\n", " ") + "\n\n")

# every place a `code` is inspected near a socket callback
out.write("=== code inspections (first 40) ===\n")
for m in list(re.finditer(r"\.code\b", CLIENT))[:40]:
    out.write("...%s...\n" % CLIENT[max(0, m.start() - 180):m.end() + 120].replace("\n", " "))

sys.stdout = io.open(os.path.join(ROOT, "logs", "socket_dispatch.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/socket_dispatch.txt")
