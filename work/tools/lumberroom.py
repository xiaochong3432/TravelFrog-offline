#!/usr/bin/env python3
"""Is the Lumberroom's 百科 button gated on something? (the player says it vanished)"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re

C = io.open(str(PROJECT_ROOT) + "/work/run/web/js/main.min.js", encoding="utf-8", errors="replace").read()
out = io.StringIO()

i = C.find("var Lumberroom=function")
j = C.find("__reflect(Lumberroom.prototype", i)
body = C[i:j]
out.write("Lumberroom body: %d chars\n\n" % len(body))
for kw in ["encyBtn", "EncyModel", "isOpen", "visible"]:
    hits = [m.start() for m in re.finditer(re.escape(kw), body)]
    out.write("--- %s : %d\n" % (kw, len(hits)))
    for h in hits[:4]:
        out.write("    ...%s...\n" % body[max(0, h - 240):h + 260].replace("\n", " "))
    out.write("\n")

# and who opens the Lumberroom itself?
out.write("=== who opens Lumberroom / LumberroomController ===\n")
for m in re.finditer(r"addViewControl\(Lumberroom[A-Za-z]*", C):
    out.write("  @%d ...%s...\n" % (m.start(),
              C[max(0, m.start() - 420):m.start() + 140].replace("\n", " ")))

io.open(str(PROJECT_ROOT) + "/work/logs/lumberroom.txt", "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/lumberroom.txt")
