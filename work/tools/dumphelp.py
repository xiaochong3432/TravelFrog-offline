#!/usr/bin/env python3
"""Dump the code around the Help view (Menu/Help.exml) so each button's action is
visible: 协议 / 联系客服 / 退出游戏 / 导入存档 / the numbered buttons."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re
import sys

JS = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
span = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
needle = sys.argv[2] if len(sys.argv) > 2 else "Menu/Help.exml"

with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()

m = re.search(re.escape(needle), s)
if not m:
    print("not found: %s" % needle)
    raise SystemExit(1)
print("@%d" % m.start())
print(s[max(0, m.start() - 300):m.start() + span])
