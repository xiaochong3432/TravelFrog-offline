#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dump a slice of the minified client starting at a literal, to a file.

Usage: python tools/dumpslice.py "var EncyView=" 9000 logs/ency_view.txt
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import sys

SRC = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
pat = sys.argv[1]
n = int(sys.argv[2])
dest = sys.argv[3]

text = io.open(SRC, encoding='utf-8', errors='replace').read()
i = text.find(pat)
if i < 0:
    print('not found: %r' % pat)
    sys.exit(1)
seg = text[i:i + n]
# break the minified stream at statement-ish boundaries so it can be read
out = io.open(dest, 'w', encoding='utf-8')
out.write('@%d  %r\n\n' % (i, pat))
buf = seg
for br in ['},t.prototype.', '},e.prototype.', ';t.prototype.', 'this.', 'var ']:
    pass
out.write(seg)
out.close()
print('wrote %s (%d chars from @%d)' % (dest, len(seg), i))
