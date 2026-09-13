#!/usr/bin/env python3
"""Search zip entries for byte patterns, without extracting whole archive."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile, re, sys

Z = str(PROJECT_ROOT) + "/base.apk"

def search(patterns, name_filter=None, ctx=120, limit=6):
    z = zipfile.ZipFile(Z)
    for i in z.infolist():
        if i.file_size > 60_000_000:
            continue
        if name_filter and not re.search(name_filter, i.filename):
            continue
        try:
            data = z.read(i)
        except Exception:
            continue
        for p in patterns:
            pb = p.encode() if isinstance(p, str) else p
            hits = list(re.finditer(re.escape(pb), data))
            if hits:
                print(f"\n### {p!r} -> {i.filename} ({len(hits)} hits)")
                for m in hits[:limit]:
                    s = max(0, m.start() - ctx); e = min(len(data), m.end() + ctx)
                    seg = data[s:e].decode("utf8", "replace").replace("\n", " ")
                    print(f"   ...{seg}...")
    z.close()

if __name__ == "__main__":
    pats = sys.argv[1:]
    search(pats, name_filter=r"classes\d*\.dex$", limit=8)
