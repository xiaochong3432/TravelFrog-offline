#!/usr/bin/env python3
"""Which view hosts the 百科 (encyclopedia) button, and who opens that view?

`on_encyBtn_tap` sits next to `on_museumBtn_tap` / `on_furnitureBtn_tap` / `on_drawBtn_tap`
/ `on_calendarBtn_tap`, so the host view is a menu with those five entries. The player
reports the 百科 entry has gone missing -- this finds the host, its skin, and its opener.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re

C = io.open(str(PROJECT_ROOT) + "/work/run/web/js/main.min.js", encoding="utf-8", errors="replace").read()
out = io.StringIO()

i = C.find("on_encyBtn_tap=function")
out.write("on_encyBtn_tap @%d\n" % i)

# walk backwards for the nearest skin-based class declaration
seg = C[:i]
decl = None
for m in re.finditer(r"var ([A-Za-z_$][A-Za-z0-9_$]*)=function\(e\)\{function t\(\)\{", seg):
    decl = m
out.write("nearest class before it: %s (at %d)\n" % (decl.group(1), decl.start()))
skins = re.findall(r"getSkinsPath\(\"([^\"]+)\"\)", C[decl.start():i])
out.write("skins inside that class: %s\n\n" % skins[-4:])

# who opens that host view?
name = decl.group(1)
for m in re.finditer(r"addViewControl\((%s)[,)]" % re.escape(name), C):
    out.write("OPENS %s: @%d ...%s...\n\n"
              % (name, m.start(), C[max(0, m.start() - 460):m.start() + 120].replace("\n", " ")))

# all five handlers, to see whether they are in the same class
for h in ["on_museumBtn_tap", "on_furnitureBtn_tap", "on_drawBtn_tap", "on_encyBtn_tap",
          "on_calendarBtn_tap"]:
    hits = [m.start() for m in re.finditer(re.escape(h) + "=function", C)]
    out.write("%-22s %s\n" % (h, hits))

io.open(str(PROJECT_ROOT) + "/work/logs/ency_entry.txt", "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/ency_entry.txt")
