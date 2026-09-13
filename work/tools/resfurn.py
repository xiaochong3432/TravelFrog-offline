#!/usr/bin/env python3
"""List default.res.json entries whose key/url mentions one of the given words."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, re, sys

p = str(PROJECT_ROOT) + "/work/base/assets/game/resource/China/default.res.json"
d = open(p, encoding="utf8", errors="replace").read()
j = json.loads(d)
words = sys.argv[1:] or ["furniture", "flowerpot", "compost", "pocket", "tumbler", "bench", "decoration"]
for res in j.get("resources", []):
    s = json.dumps(res, ensure_ascii=False)
    if any(w.lower() in s.lower() for w in words):
        print(s)
