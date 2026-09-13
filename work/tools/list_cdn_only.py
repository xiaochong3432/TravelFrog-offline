#!/usr/bin/env python3
"""List the CDN-only files, grouped, to judge whether they matter for v1001."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os, collections

d = json.load(open(str(PROJECT_ROOT) + "/work/cdn/patch.json", encoding="utf8"))
files = {k: v for k, v in d.items() if not k.startswith("__")}
WEB = str(PROJECT_ROOT) + "/work/run/web"

missing = [p for p in files
           if not os.path.isfile(os.path.join(WEB, p.replace("/", os.sep)))]
print(f"CDN-only (not in our tree): {len(missing)}")

by_dir = collections.defaultdict(list)
for p in missing:
    by_dir["/".join(p.split("/")[:-1])].append(os.path.basename(p))

for d0 in sorted(by_dir, key=lambda k: -len(by_dir[k]))[:20]:
    names = by_dir[d0]
    print(f"\n{d0}  ({len(names)})")
    for n in sorted(names)[:8]:
        print("    ", n)
    if len(names) > 8:
        print(f"     ... +{len(names) - 8} more")

# are these referenced by v1001 code?
v1 = open(os.path.join(WEB, "js", "main.min.js"), "rb").read()
print("\n--- do v1001's code/theme reference these paths? ---")
for token in ["PictureData", "TravelData", "MainData", "HandCraft", "FurnitureData"]:
    print(f"  {token:<16} in main.min.js: {token.encode() in v1}")
