#!/usr/bin/env python3
"""Dump the client's DataManager table registry and locate matching resources."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, json, os

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
data = open(JS, "rb").read().decode("utf8", "replace")

i = 451542
print("===== DataManager init region =====")
print(data[i - 1500:i + 2500])

print("\n\n===== all RES.getRes(\"..\") =====")
for m in sorted(set(re.findall(r'RES\.getRes\("([^"]+)"\)', data))):
    print("   ", m)

print("\n===== helper-loaded tables like i(\"x\") near DataManager =====")
seg = data[i - 200:i + 6000]
for m in sorted(set(re.findall(r'\bi\("([A-Za-z0-9_]+)"\)', seg))):
    print("   ", m)

print("\n===== version.json entries matching table names =====")
vj = json.load(open(str(PROJECT_ROOT) + "/work/base/assets/game/version.json", encoding="utf8"))
want = ["resources", "gameplay", "visitors", "step", "decoration", "Picture", "PictureTag",
        "Note", "Word", "TravelFriends", "pray", "recharge"]
for k in vj:
    kl = k.lower()
    if any(w.lower() in kl for w in want):
        print("   ", k)
print(f"(version.json has {len(vj)} entries)")
