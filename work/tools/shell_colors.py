#!/usr/bin/env python3
"""Find the red square's definition: every `background` / colour literal in the shell."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re

out = io.StringIO()
for f in [str(PROJECT_ROOT) + "/work/run/web/__probe.js", str(PROJECT_ROOT) + "/work/run/web/index.html"]:
    t = io.open(f, encoding="utf-8", errors="replace").read()
    out.write("=" * 70 + "\n=== %s\n" % f)
    for m in re.finditer(r"background|rgba?\(|#[0-9a-fA-F]{3,8}\b", t):
        a = max(0, m.start() - 120)
        seg = t[a:m.start() + 160].replace("\n", " ")
        out.write("  @%-7d %s\n" % (m.start(), seg))
    out.write("\n")
io.open(str(PROJECT_ROOT) + "/work/logs/shell_colors.txt", "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/shell_colors.txt")
