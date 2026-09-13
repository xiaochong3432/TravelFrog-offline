#!/usr/bin/env python3
"""Extract a whole client model class (start .. __reflect) and show its key methods.

The four activity models are long, so a fixed-size window misses isOpen(); this
takes the class body by its real boundaries and then pulls out the methods that
decide the event window.
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
C = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
            encoding="utf-8", errors="replace").read()
out = io.StringIO()

MODELS = sys.argv[1:] or ["MuseumDayModel", "PartyCakeModel", "SpringCardModel", "GreetCardModel"]
METHODS = ["isOpen", "getActivityTime", "checkRedot", "getLeftTime", "getData"]

for m in MODELS:
    i = C.find(m + "=function")
    end = C.find('__reflect(%s.prototype' % m, i)
    body = C[i:end if end > 0 else i + 9000]
    out.write("=" * 78 + "\n=== %s  (%d chars, @%d)\n" % (m, len(body), i))
    for meth in METHODS:
        for hit in re.finditer(r"t\.prototype\.%s=function" % meth, body):
            k = body.find(",t.prototype.", hit.end())
            seg = body[hit.end():k if k > 0 else hit.end() + 1200]
            out.write("  --- %s\n  %s\n" % (meth, seg.replace("\n", " ")[:1200]))
    # the load handler in full
    for hit in re.finditer(r"t\.prototype\.([a-z_]+_load)=function", body):
        k = body.find(",t.prototype.", hit.end())
        seg = body[hit.end():k if k > 0 else hit.end() + 2000]
        out.write("  --- %s\n  %s\n" % (hit.group(1), seg.replace("\n", " ")[:2000]))
    out.write("\n")

sys.stdout = io.open(os.path.join(ROOT, "logs", "event_windows.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/event_windows.txt (%d chars)" % len(out.getvalue()))
