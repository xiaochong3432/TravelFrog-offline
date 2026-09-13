#!/usr/bin/env python3
"""Temporary diagnostic: make the offline enterGame path announce itself."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os, shutil

MAIN = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
d = open(MAIN, encoding="utf8").read()

OLD = 'true&&(Music.play("BGM_Default"'
NEW = '(window.console&&console.log("[offline] enterGame body reached"),true)&&(Music.play("BGM_Default"'

n = d.count(OLD)
print("occurrences of patched guard:", n)
if 'enterGame body reached' in d:
    print("diagnostic already present")
elif n:
    d = d.replace(OLD, NEW)
    open(MAIN, "w", encoding="utf8").write(d)
    print("diagnostic inserted")
else:
    # fall back: report what the enterGame definitions look like
    i = 0
    while True:
        i = d.find("prototype.enterGame=function", i + 1)
        if i < 0:
            break
        print("---", d[i:i + 260])
