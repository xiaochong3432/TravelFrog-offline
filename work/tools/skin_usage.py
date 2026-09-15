#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Search the client's skin bundle (config.eab) for a texture name, and dump one skin.

Why: button_02_png is the art for the Help panel's 客服 button -- the label is DRAWN INTO
the image, so renaming the menu entry means replacing that texture. Before doing so I need
to know how many screens reference it.
"""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 2），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import struct
import sys

sys.path.insert(0, str(PROJECT_ROOT) + "/work/tools")
import eab_dec  # noqa: E402

BUNDLE = str(PROJECT_ROOT) + "/work/run/v3web/resource/China/eab/config.eab"
NEEDLE = 'button_02_png'
OUT = str(PROJECT_ROOT) + "/work/logs/skin_button_usage.txt"

entries, payload = eab_dec.decode(BUNDLE)
out = io.open(OUT, 'w', encoding='utf-8')
out.write('config.eab: %d entries, payload %d bytes\n' % (len(entries), len(payload)))

hits = []
exmls = 0
for name, (off, size, e) in entries.items():
    if not name.endswith('.exml'):
        continue
    exmls += 1
    blob = payload[off:off + size]
    if NEEDLE.encode('utf-8') in blob:
        hits.append(name)
out.write('skins (.exml entries): %d\n' % exmls)
out.write('skins referencing %s: %d\n' % (NEEDLE, len(hits)))
for h in hits:
    out.write('   %s\n' % h)

# dump Menu/Help.exml so the button/label structure is evidenced, not assumed
for want in ['Menu/Help.exml', 'Menu/Customer.exml']:
    if want in entries:
        off, size, e = entries[want]
        blob = payload[off:off + size]
        out.write('\n===== %s (%d bytes) =====\n' % (want, size))
        text = blob.decode('utf-8', 'replace')
        out.write(text[:4000])
        out.write('\n')
out.close()
print('wrote logs/skin_button_usage.txt : %d skins reference the texture' % len(hits))
