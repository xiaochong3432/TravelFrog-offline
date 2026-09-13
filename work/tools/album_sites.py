#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Locate how AlbumController is opened and what skin its view uses."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re

SRC = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
OUT = str(PROJECT_ROOT) + "/work/logs/album_sites.txt"

text = io.open(SRC, encoding='utf-8', errors='replace').read()
out = io.open(OUT, 'w', encoding='utf-8')
out.write('file %s (%d bytes)\n' % (SRC, len(text)))

for pat in ['AlbumController', 'album', 'AlbumView', 'travelmap']:
    hits = [m.start() for m in re.finditer(re.escape(pat), text)]
    out.write('\n=== %r : %d hits\n' % (pat, len(hits)))
    for i in hits[:8]:
        a = max(0, i - 260)
        b = min(len(text), i + 260)
        out.write('  @%d ...%s...\n\n' % (i, text[a:b].replace('\n', ' ')))

# the class whose constructor wires travelMapBtn -- walk back to "var X=function"
i = text.find('this.on_travelMapBtn,this)')
out.write('\n=== enclosing class of travelMapBtn (@%d)\n' % i)
seg = text[max(0, i - 6000):i]
for m in re.finditer(r'var ([A-Za-z_$][\w$]*)=function\(', seg):
    pass
names = re.findall(r'var ([A-Za-z_$][\w$]*)=function\(', seg)
out.write('candidates: %s\n' % names[-6:])
out.close()
print('wrote logs/album_sites.txt')
