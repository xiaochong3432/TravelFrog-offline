#!/usr/bin/env python3
"""Show the client's callbacks for the 8 getErrorInfo commands, so we know a
nonzero-but-known code really produces a visible message."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import re
import sys

ROOT = str(PROJECT_ROOT) + "/work"
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()
NAMES = ["album_delete", "album_recover", "album_save_new", "item_use_gift_code",
         "travel_album_to_gift", "travel_bag_to_gift", "travel_gift_to_album",
         "travel_gift_to_bag"]

out = io.StringIO()
for n in NAMES:
    for m in re.finditer(r'send\(\s*"%s"' % re.escape(n), CLIENT):
        out.write("=== %s @%d\n" % (n, m.start()))
        out.write(CLIENT[m.start():m.start() + 700].replace("\n", " ") + "\n\n")
        break

out.write("=== help menu entries (礼包码兑换 / gift code) ===\n")
for kw in ["礼包码", "gift_code", "giftCode", "兑换"]:
    for m in re.finditer(re.escape(kw), CLIENT):
        out.write("[%s] @%d ...%s...\n"
                  % (kw, m.start(),
                     CLIENT[max(0, m.start() - 220):m.end() + 220].replace("\n", " ")))
        break
sys.stdout = open(os.path.join(ROOT, "logs", "silent_callbacks.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/silent_callbacks.txt")
