#!/usr/bin/env python3
"""Verify the offline patches are present in the served main.min.js and dump EventType."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import urllib.request, re, os

url = "http://127.0.0.1:8080/js/main.min.js"
try:
    body = urllib.request.urlopen(url, timeout=20).read().decode("utf8", "replace")
    print(f"served main.min.js: {len(body)} chars")
    print("  patched guard present :", 'true&&(Music.play("BGM_Default"' in body)
    print("  original guard present:", "this.loadComplete&&NetworkControl.getInstance().isSyncComplete()" in body)
except Exception as e:
    print("fetch failed:", e)

f = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
d = open(f, encoding="utf8").read()
i = d.find("EventType_")
print("\nEventType samples in served file:")
for m in sorted(set(re.findall(r'EventType_[A-Za-z]+', d)))[:20]:
    print("   ", m)
