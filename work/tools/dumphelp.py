#!/usr/bin/env python3
"""Dump the code around the Help view (Menu/Help.exml) so each button's action is
visible: 协议 / 联系客服 / 退出游戏 / 导入存档 / the numbered buttons."""
import re
import sys

JS = r"H:\AI\frog\work\run\web\js\main.min.js"
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
