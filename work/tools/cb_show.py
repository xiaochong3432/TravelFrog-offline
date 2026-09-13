#!/usr/bin/env python3
"""Print the client's `send("<cmd>", new core.ActionN(function(...){...}))` body.

Usage: python tools/cb_show.py item_buy item_gacha ...
Useful for judging what a client callback actually DOES with a reply code:
  * `getErrorInfo(n.code)`      -> an unknown code is silent (or, worse, reads as
                                   success, because `o && ...` fails open/shut
                                   depending on how the branch is written)
  * `0 == n.code ? ... : ...`   -> the callback carries its own message
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import re
import sys

ROOT = str(PROJECT_ROOT) + "/work"
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()

names = sys.argv[1:]
out = io.StringIO()
for n in names:
    pat = re.compile(r'send\(\s*"%s"' % re.escape(n))
    hits = list(pat.finditer(CLIENT))
    out.write("=== %s  (%d send sites)\n" % (n, len(hits)))
    for m in hits[:2]:
        out.write(CLIENT[m.start():m.start() + 900].replace("\n", " ") + "\n\n")

sys.stdout = io.open(os.path.join(ROOT, "logs", "cb_show.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/cb_show.txt (%d chars)" % len(out.getvalue()))
