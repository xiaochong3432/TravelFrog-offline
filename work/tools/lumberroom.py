#!/usr/bin/env python3
"""Is the Lumberroom's 百科 button gated on something? (the player says it vanished)"""
import io
import re

C = io.open(r"H:\AI\frog\work\run\web\js\main.min.js", encoding="utf-8", errors="replace").read()
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

io.open(r"H:\AI\frog\work\logs\lumberroom.txt", "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/lumberroom.txt")
