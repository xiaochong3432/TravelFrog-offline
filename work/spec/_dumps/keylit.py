#!/usr/bin/env python3
"""Dump the exact chars of the eab XXTEA key literal."""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re
JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

i = d.index("Utils.simpleEncrypt(")
seg = d[i:i + 120]
print("raw repr:", repr(seg[:80]))
m = re.search(r'simpleEncrypt\("([^"]*)",\s*(\d+)\)', d[i:i + 200])
print("match:", m)
lit = m.group(1)
print("len", len(lit), "codes", [ord(c) for c in lit])
