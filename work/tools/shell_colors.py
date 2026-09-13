#!/usr/bin/env python3
"""Find the red square's definition: every `background` / colour literal in the shell."""
import io
import re

out = io.StringIO()
for f in [r"H:\AI\frog\work\run\web\__probe.js", r"H:\AI\frog\work\run\web\index.html"]:
    t = io.open(f, encoding="utf-8", errors="replace").read()
    out.write("=" * 70 + "\n=== %s\n" % f)
    for m in re.finditer(r"background|rgba?\(|#[0-9a-fA-F]{3,8}\b", t):
        a = max(0, m.start() - 120)
        seg = t[a:m.start() + 160].replace("\n", " ")
        out.write("  @%-7d %s\n" % (m.start(), seg))
    out.write("\n")
io.open(r"H:\AI\frog\work\logs\shell_colors.txt", "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/shell_colors.txt")
