#!/usr/bin/env python3
"""List the scripts launcher.js loads, from the little manifest it fetches."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
import os
import re

WEB = str(PROJECT_ROOT) + "/work/run/web"

with open(os.path.join(WEB, "launcher.js"), encoding="utf-8", errors="replace") as fh:
    t = fh.read()

print("--- .js names referenced in launcher.js ---")
for m in re.finditer(r"""[A-Za-z0-9_./\-]+\.js""", t):
    print("  ", m.group(0))

print("\n--- manifests present on disk ---")
for f in os.listdir(WEB):
    if f.endswith(".json"):
        print("  ", f, os.path.getsize(os.path.join(WEB, f)))

for cand in ("version.json", "manifest.json", "gameConfig.json", "config.json"):
    p = os.path.join(WEB, cand)
    if os.path.isfile(p):
        with open(p, encoding="utf-8", errors="replace") as fh:
            print("\n== %s ==" % cand)
            print(fh.read()[:1500])
