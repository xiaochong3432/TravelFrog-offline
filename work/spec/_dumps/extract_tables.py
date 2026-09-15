#!/usr/bin/env python3
"""Extract all JSON tables from config.eab into work/spec/_dumps/tables/."""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eabdec

SRC = str(PROJECT_ROOT) + "/work/run/web/resource/China/eab/config.eab"
OUT = str(PROJECT_ROOT) + "/work/spec/_dumps/tables"
os.makedirs(OUT, exist_ok=True)

plain, index, off = eabdec.decode(SRC)
pos = off
for e in index:
    s = e.get("s", 0)
    blob = plain[pos:pos + s]
    pos += s
    name = e["n"].replace("_json", "") + ".json"
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(blob)
print("extracted %d tables -> %s" % (len(index), OUT))
