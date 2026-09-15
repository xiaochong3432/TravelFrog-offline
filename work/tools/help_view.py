#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Locate the client's Help view (the menu with 协议 / 联系客服 / 退出游戏) so the shell
can relabel its 客服 button at runtime and a probe can open it directly."""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 2），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re

SRC = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
OUT = str(PROJECT_ROOT) + "/work/logs/help_view.txt"

t = io.open(SRC, encoding='utf-8', errors='replace').read()
out = io.open(OUT, 'w', encoding='utf-8')

i = t.find('this.btn_customer.addEventListener')
seg = t[max(0, i - 20000):i]
names = re.findall(r'var ([A-Za-z_$][\w$]*)=function\(', seg)
out.write('enclosing class candidates: %r\n' % names[-5:])

# the skin the view loads
for m in re.finditer(r'getSkinsPath\("([^"]+)"\)', seg):
    out.write('skin in that region: %r\n' % m.group(1))

# who opens it
cls = names[-1] if names else '?'
out.write('\nopened via (searching addViewControl):\n')
for m in re.finditer(r'addViewControl\(([A-Za-z_$][\w$]*)', t):
    pass
hits = [m.group(1) for m in re.finditer(r'addViewControl\(([A-Za-z_$][\w$]*)[,)]', t)]
from collections import Counter
out.write('  most common controllers: %r\n' % Counter(hits).most_common(12))
for name in ['HelpViewControl', 'HelpView', 'SettingViewControl']:
    j = t.find('addViewControl(' + name)
    out.write('  %-20s call site: %d\n' % (name, j))

# the class definition of the view that owns btn_customer
j = t.find('.prototype.totalTouchEvents=function')
out.write('\ntotalTouchEvents handler (@%d):\n' % j)
out.write(t[j:j + 1800].replace('\n', ' ') + '\n')

out.write('\nskin files mentioning Help:\n')
for m in sorted(set(re.findall(r'getSkinsPath\("([^"]*[Hh]elp[^"]*)"\)', t))):
    out.write('  %r\n' % m)
out.write('\nall Menu/* skins:\n')
for m in sorted(set(re.findall(r'getSkinsPath\("(Menu/[^"]*)"\)', t))):
    out.write('  %r\n' % m)
out.close()
print('wrote logs/help_view.txt')
