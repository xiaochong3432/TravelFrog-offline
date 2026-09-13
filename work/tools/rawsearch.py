#!/usr/bin/env python3
"""Raw byte search for a UTF-8 string across web resources (incl. odd-format bundles)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os, sys

WEB = str(PROJECT_ROOT) + "/work/run/web"
OUT = str(PROJECT_ROOT) + "/work/rawsearch.txt"
needles = sys.argv[1:] or ["开始", "这里有只青蛙", "呱呱"]
lines = []


def out(s):
    lines.append(s)


for needle in needles:
    nb = needle.encode("utf8")
    out(f"\n===== {needle!r} =====")
    total = 0
    for root, dirs, files in os.walk(WEB):
        for fn in files:
            p = os.path.join(root, fn)
            try:
                if os.path.getsize(p) > 30_000_000:
                    continue
                d = open(p, "rb").read()
            except OSError:
                continue
            i = d.find(nb)
            if i >= 0:
                rel = os.path.relpath(p, WEB)
                out(f"  {rel}  @{i}")
                out("      " + d[max(0, i - 100):i + 120].decode("utf8", "replace").replace("\n", " "))
                total += 1
    out(f"  files: {total}")

open(OUT, "w", encoding="utf8").write("\n".join(lines))
print(f"wrote {OUT} ({len(lines)} lines)")
