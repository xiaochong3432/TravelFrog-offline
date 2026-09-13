#!/usr/bin/env python3
"""Show the context around `new GuideNamedView(...)` -- what opens the guide's
naming step, and what its completion callback does."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import sys

ROOT = str(PROJECT_ROOT) + "/work"
C = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
            encoding="utf-8", errors="replace").read()
out = io.StringIO()
i = C.find("new GuideNamedView")
out.write(C[max(0, i - 2600):i + 2200].replace("\n", " ") + "\n")
sys.stdout = io.open(os.path.join(ROOT, "logs", "guidename2.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/guidename2.txt")
