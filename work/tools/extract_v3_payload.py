#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract the V3 APK's web payload into work/run/v3web/ so it can be patched and then
packed with OUR wrapper.

V3 ships the page at `assets/` (not `assets/game/`), loaded from file:// by its own minimal
WebView. Our wrapper serves `assets/game/**` over 127.0.0.1, so the payload is staged here
with the same internal layout and the build is pointed at this directory.
"""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 2），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import shutil
import sys
import zipfile

ROOT = str(PROJECT_ROOT)
SRC = os.path.join(ROOT, "work", "build", "v3", "V3.apk")
DEST = os.path.join(ROOT, "work", "run", "v3web")


def log(*a):
    enc = getattr(sys.stdout, "encoding", None) or "utf-8"
    print(*[str(x).encode(enc, "replace").decode(enc, "replace") for x in a], flush=True)


def main():
    if not os.path.isfile(SRC):
        log('!! missing ' + SRC)
        return 1
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    os.makedirs(DEST)

    n = 0
    raw = 0
    with zipfile.ZipFile(SRC) as z:
        for name in z.namelist():
            if not name.startswith("assets/") or name.endswith("/"):
                continue
            rel = name[len("assets/"):]
            out = os.path.join(DEST, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with z.open(name) as fh, open(out, "wb") as w:
                data = fh.read()
                w.write(data)
            n += 1
            raw += len(data)

    log("extracted %d files (%.1f MB) -> %s" % (n, raw / 1048576, DEST))
    for k in ["index.html", "__probe.js", "__offline-engine.js", "map.html", "version.json"]:
        p = os.path.join(DEST, k)
        log("   %-22s %s" % (k, os.path.getsize(p) if os.path.isfile(p) else "MISSING"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
