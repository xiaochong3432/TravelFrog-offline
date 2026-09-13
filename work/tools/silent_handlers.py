#!/usr/bin/env python3
"""Show the engine's handler bodies for the 8 commands whose -1 reply is SILENT."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import re
import sys

ROOT = str(PROJECT_ROOT) + "/work"
ENGINE = io.open(os.path.join(ROOT, "run", "engine", "index.js"), encoding="utf-8").read()
NAMES = ["album_delete", "album_recover", "album_save_new", "item_use_gift_code",
         "travel_album_to_gift", "travel_bag_to_gift", "travel_gift_to_album",
         "travel_gift_to_bag"]

marks = [(m.group(1), m.start()) for m in
         re.finditer(r"^    ([A-Za-z_][A-Za-z0-9_]*):\s*\(", ENGINE, re.M)]
marks.append((None, len(ENGINE)))

out = io.StringIO()
for i in range(len(marks) - 1):
    name, start = marks[i]
    if name not in NAMES:
        continue
    end = min(marks[i + 1][1], start + 2200)
    out.write("=== %s ===\n" % name)
    out.write(ENGINE[start:end])
    out.write("\n")
sys.stdout = open(os.path.join(ROOT, "logs", "silent_handlers.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/silent_handlers.txt")
