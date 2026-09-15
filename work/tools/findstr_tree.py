#!/usr/bin/env python3
"""Find a UTF-8 string anywhere under the web tree, including inside .eab bundles."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os, sys, json, struct

WEB = str(PROJECT_ROOT) + "/work/run/web"
needle = sys.argv[1].encode("utf8") if len(sys.argv) > 1 else "这里有只青蛙".encode("utf8")


def eab_entries(path):
    d = open(path, "rb").read()
    if d[:8] != b"\x89EAB\r\n\x1a\n":
        return None
    (idxlen,) = struct.unpack_from("<I", d, 8)
    man = json.loads(d[12:12 + idxlen].decode("utf8"))
    off = 12 + idxlen
    out = []
    for e in man:
        s = e.get("s", 0)
        out.append((e["n"], off, s, e))
        off += s
    return d, out


hits = 0
for root, dirs, files in os.walk(WEB):
    for fn in files:
        p = os.path.join(root, fn)
        rel = os.path.relpath(p, WEB)
        try:
            if fn.endswith(".eab"):
                got = eab_entries(p)
                if not got:
                    continue
                d, ents = got
                for name, off, size, meta in ents:
                    blob = d[off:off + size]
                    if needle in blob:
                        print(f"  EAB {rel} :: entry {name} ({size} bytes)")
                        i = blob.find(needle)
                        print("      ctx:", blob[max(0, i - 120):i + 160].decode("utf8", "replace").replace("\n", " "))
                        hits += 1
            elif os.path.getsize(p) < 20_000_000:
                d = open(p, "rb").read()
                if needle in d:
                    i = d.find(needle)
                    print(f"  FILE {rel}")
                    print("      ctx:", d[max(0, i - 120):i + 160].decode("utf8", "replace").replace("\n", " "))
                    hits += 1
        except Exception as ex:
            pass
print(f"\nhits: {hits}")
