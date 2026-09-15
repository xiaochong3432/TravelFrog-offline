#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Every call site that opens AlbumController, with the enclosing class name, so the
player-reachable entry (menu button / shelf item) can be identified."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re

SRC = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
OUT = str(PROJECT_ROOT) + "/work/logs/album_entry.txt"

text = io.open(SRC, encoding='utf-8', errors='replace').read()
out = io.open(OUT, 'w', encoding='utf-8')

CLS = re.compile(r'var ([A-Za-z_$][\w$]*)=function\(')


def enclosing(pos):
    best = '?'
    for m in CLS.finditer(text):
        if m.start() < pos:
            best = m.group(1)
        else:
            break
    return best


for pat in ['addViewControl(AlbumController', 'AlbumController,']:
    hits = [m.start() for m in re.finditer(re.escape(pat), text)]
    out.write('\n=== %r : %d hits\n' % (pat, len(hits)))
    for i in hits:
        out.write('\n  @%d in class %s\n    ...%s...\n'
                  % (i, enclosing(i), text[max(0, i - 300):i + 200].replace('\n', ' ')))

out.write('\n=== literal 相册 (button labels)\n')
for m in re.finditer('相册', text):
    out.write('  @%d [%s] ...%s...\n' % (m.start(), enclosing(m.start()),
                                         text[max(0, m.start() - 160):m.start() + 80].replace('\n', ' ')))
out.close()
print('wrote logs/album_entry.txt')
