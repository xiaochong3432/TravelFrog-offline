#!/usr/bin/env python3
"""Show the context around `new GuideNamedView(...)` -- what opens the guide's
naming step, and what its completion callback does."""
import io
import os
import sys

ROOT = r"H:\AI\frog\work"
C = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
            encoding="utf-8", errors="replace").read()
out = io.StringIO()
i = C.find("new GuideNamedView")
out.write(C[max(0, i - 2600):i + 2200].replace("\n", " ") + "\n")
sys.stdout = io.open(os.path.join(ROOT, "logs", "guidename2.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/guidename2.txt")
