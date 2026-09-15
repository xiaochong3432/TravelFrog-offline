#!/usr/bin/env python3
"""List / extract entries from the China .eab bundles (config tables live in config.eab)."""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import sys, os, json, struct


def load(path):
    d = open(path, "rb").read()
    assert d[:6] == b"\x89EAB\r\n" and d[7] == 0x0A, "not an eab: %r" % d[:8]
    (idxlen,) = struct.unpack_from("<I", d, 8)
    man = json.loads(d[12:12 + idxlen].decode("utf8"))
    pos = 12 + idxlen
    entries = {}
    for e in man:
        size = e.get("s", 0)
        entries[e["n"]] = (pos, size, e)
        pos += size
    return d, entries, pos


eab = sys.modules[__name__]
BASE = str(PROJECT_ROOT) + "/work/run/web/resource/China/eab"
for f in sorted(os.listdir(BASE)):
    if not f.endswith(".eab"):
        continue
    d, entries, end = load(os.path.join(BASE, f))
    hit = [n for n in entries if any(k in n.lower() for k in
           ("note", "picture", "collection", "specialty", "item", "resources", "word", "travel"))]
    if hit:
        print("=" * 20, f, len(entries), "entries")
        for n in hit:
            o, s, e = entries[n]
            print("   %-40s off=%-9d size=%-9d type=%s" % (n, o, s, e.get("t")))
