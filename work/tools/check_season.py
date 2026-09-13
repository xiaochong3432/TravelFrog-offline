#!/usr/bin/env python3
"""Check the season group contents and whether the files exist in the web tree."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os

RES = str(PROJECT_ROOT) + "/work/run/web/resource/China/default.res.json"
WEB = str(PROJECT_ROOT) + "/work/run/web"
d = json.load(open(RES, encoding="utf8"))

groups = {g["name"]: g.get("keys", "").split(",") for g in d.get("groups", [])}
byname = {r["name"]: r for r in d.get("resources", [])}

for gname in ("season11", "mainout"):
    keys = groups.get(gname, [])
    print(f"\n=== group {gname}: {len(keys)} keys ===")
    for k in keys:
        r = byname.get(k)
        url = r.get("url") if r else None
        exists = os.path.exists(os.path.join(WEB, url)) if url else False
        print(f"  {k:<42} url={url} exists={exists}")
