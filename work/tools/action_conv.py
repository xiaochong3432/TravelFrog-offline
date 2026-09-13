#!/usr/bin/env python3
"""Pin down the Action callback convention.

AnalysisProtocol does `s.apply(r.data, o.data)` where o is the stored request
envelope. `u.data` is built as an OBJECT (`u.data[name]=value`), and
Function.prototype.apply with a non-array-like object supplies ZERO arguments,
leaving `this` = r.data (the reply). Verify the class names, arities and a few
real call sites before drawing any conclusion about error codes.
"""
import io
import os
import re
import sys

ROOT = r"H:\AI\frog\work"
C = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
            encoding="utf-8", errors="replace").read()
out = io.StringIO()

for kw in ["Action1=function", "Action2=function", "Action3=function",
           "Action0=function", "function Action"]:
    i = C.find(kw)
    out.write("=== %s @%d\n" % (kw, i))
    if i >= 0:
        out.write(C[i:i + 900].replace("\n", " ") + "\n\n")

out.write("=== how callbacks are written at real call sites ===\n")
for m in list(re.finditer(r"send\(\s*\"[a-z0-9_]+\"\s*,\s*new\s+core\.Action(\d)\(", C))[:14]:
    out.write("--- Action%s @%d\n%s\n\n"
              % (m.group(1), m.start(), C[m.start():m.start() + 340].replace("\n", " ")))

# `callbackFun` usage
for m in list(re.finditer(r"callbackFun", C))[:6]:
    out.write("...callbackFun... %s\n" % C[max(0, m.start() - 300):m.end() + 300].replace("\n", " "))

sys.stdout = io.open(os.path.join(ROOT, "logs", "action_conv.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/action_conv.txt")
