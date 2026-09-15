#!/usr/bin/env python3
"""Dump the shell's installSaveTools verbatim so it can be replaced wholesale."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

P = str(PROJECT_ROOT) + "/work/run/web/__probe.js"
t = io.open(P, encoding="utf-8").read()
i = t.find("    function installSaveTools()")
j = t.find("    /* --------------------------------------------------- main watchdog */")
assert i > 0 and j > i, (i, j)
io.open(str(PROJECT_ROOT) + "/work/logs/savetools_src.txt", "w", encoding="utf-8").write(t[i:j])
print("start=%d end=%d len=%d" % (i, j, j - i))
print("installOfflineAds call sites:", t.count("installOfflineAds();"))
