#!/usr/bin/env python3
"""Show the engine's item_load_items / album_load_all / album_load / unlock_pictures."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re

P = str(PROJECT_ROOT) + "/work/run/engine/index.js"
t = io.open(P, encoding="utf-8").read()
out = io.StringIO()

for pat in [r"    item_load_items: ", r"    album_load_all: ", r"    album_load: "]:
    for m in re.finditer(pat, t):
        out.write("=== L%d %s\n" % (t.count("\n", 0, m.start()) + 1, pat.strip()))
        seg = t[m.start():m.start() + 900]
        out.write(seg.split("\n\n")[0][:850] + "\n\n")

for case in ["unlock_pictures", "add_specialty"]:
    i = t.find("case '" + case + "'")
    if i < 0:
        out.write("=== %s: NOT FOUND\n\n" % case)
        continue
    out.write("=== case %s  L%d\n" % (case, t.count("\n", 0, i) + 1))
    out.write(t[i:i + 700] + "\n\n")

io.open(str(PROJECT_ROOT) + "/work/logs/album_items.txt", "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/album_items.txt")
