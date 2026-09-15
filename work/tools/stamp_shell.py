#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rewrite the 存档编辑 panel's BUILD_STAMP to the current local time.

The stamp is how a player can tell which copy of the game they are running, so it has to
be the moment of the build -- hand-editing it produced a stamp 17 minutes in the future
(clock drift between writing the patch and running the build). Run this immediately
before build_wrapper_apk.py.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import datetime
import io
import re

SHELL = str(PROJECT_ROOT) + "/work/run/web/__probe.js"

now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
text = io.open(SHELL, encoding='utf-8').read()
new, n = re.subn(r"var BUILD_STAMP = '[^']*';",
                 "var BUILD_STAMP = '%s';" % now, text)
assert n == 1, 'expected exactly one BUILD_STAMP, found %d' % n
if new != text:
    io.open(SHELL, 'w', encoding='utf-8', newline='').write(new)
print('BUILD_STAMP -> %s' % now)
