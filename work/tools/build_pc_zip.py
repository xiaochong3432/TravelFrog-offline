#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the "unzip and play" PC package: dist/TravelFrog-PC.zip

Layout inside the zip (the launchers expect `web/` next to them):

    TravelFrog-PC/
      旅行青蛙.exe          double-click entry: no Python, no execution policy
                           (compiled against the .NET Framework Windows ships with)
      play_frog.bat        fallback entry (Python if present, else PowerShell)
      play_frog.py         Python launcher
      play-pc.ps1          dependency-free Windows launcher (HttpListener)
      说明-先看这个.txt      full feature list / how to play / what is ours
      web/                 the game itself (index.html + js + resource + engine)

Why a launcher at all: browsers refuse XHR from file://, so double-clicking index.html
cannot work. The launchers serve the folder read-only on 127.0.0.1.

Art (png/mp3/mp4/eab) is already compressed, so it is STORED; text is deflated.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import shutil
import sys
import time
import zipfile

ROOT = str(PROJECT_ROOT)
DIST = os.path.join(ROOT, "dist")
WEB = os.path.join(ROOT, "work", "run", "web")
STAGE = os.path.join(ROOT, "work", "build", "pc", "TravelFrog-PC")
OUT = os.path.join(DIST, "TravelFrog-PC.zip")

# never ship these
SKIP_NAMES = {"__captest.html"}
SKIP_SUFFIX = (".clean", ".orig", ".bak", ".map")
STORED_EXT = {".png", ".jpg", ".jpeg", ".mp3", ".mp4", ".eab", ".gif", ".zip"}

LAUNCHERS = [
    ("旅行青蛙.exe", "旅行青蛙.exe"),
    ("play_frog.bat", "play_frog.bat"),
    ("play_frog.py", "play_frog.py"),
    ("play-pc.ps1", "play-pc.ps1"),
]
# The player manual has been renamed more than once (说明书.txt -> 说明书-V2.txt); accept any
# of them so a rename cannot stop the packaging, and never ship a package without one.
DOC_CANDIDATES = ["说明书.txt", "说明书-V2.txt", "说明-V2.txt", "说明.txt", "说明-先看这个.txt"]
DOC_DEST = "说明-先看这个.txt"
DOC_FALLBACK = """旅行青蛙·中国之旅 —— 离线单机版（PC）

解压后双击「旅行青蛙.exe」开始游戏（不需要安装任何东西）。
如果它被系统拦下，可以改用 play_frog.bat / play_frog.py / play-pc.ps1，效果相同。

游戏文件在 web 子目录里，请保留整个文件夹一起解压。
存档在浏览器里；进游戏后点画面左侧那颗圆球即可「导出存档 / 导入存档」搬家。
"""


def log(*a):
    enc = getattr(sys.stdout, "encoding", None) or "utf-8"
    print(*[str(x).encode(enc, "replace").decode(enc, "replace") for x in a], flush=True)


def main():
    if not os.path.isfile(os.path.join(WEB, "index.html")):
        log("!! no index.html in", WEB)
        return 1
    if not os.path.isfile(os.path.join(WEB, "__offline-engine.js")):
        log("!! the inlined engine is missing; run tools/bundle_engine.py first")
        return 1

    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE)

    # ---- launchers + docs (top level, next to web/)
    docs = []
    for src_name, dst_name in LAUNCHERS:
        src = os.path.join(DIST, src_name)
        if not os.path.isfile(src):
            log("!! missing launcher:", src)
            return 1
        shutil.copy2(src, os.path.join(STAGE, dst_name))
        docs.append((dst_name, src))
        log("  + %s" % dst_name)
    manual = next((os.path.join(DIST, n) for n in DOC_CANDIDATES
                   if os.path.isfile(os.path.join(DIST, n))), None)
    if manual:
        shutil.copy2(manual, os.path.join(STAGE, DOC_DEST))
        log("  + %s  (from %s)" % (DOC_DEST, os.path.basename(manual)))
    else:
        with io.open(os.path.join(STAGE, DOC_DEST), "w", encoding="utf-8") as fh:
            fh.write(DOC_FALLBACK)
        log("  + %s  (fallback: no manual found in dist/)" % DOC_DEST)
    docs.append((DOC_DEST, None))

    # ---- the game
    files = 0
    raw = 0
    t0 = time.time()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for dp, dn, fn in os.walk(WEB):
            for f in sorted(fn):
                if f in SKIP_NAMES or f.lower().endswith(SKIP_SUFFIX):
                    continue
                full = os.path.join(dp, f)
                rel = os.path.relpath(full, WEB).replace("\\", "/")
                ext = os.path.splitext(f)[1].lower()
                if ext in STORED_EXT:
                    zi = zipfile.ZipInfo.from_file(full, "TravelFrog-PC/web/" + rel)
                    zi.compress_type = zipfile.ZIP_STORED
                    with io.open(full, "rb") as fh:
                        z.writestr(zi, fh.read())
                else:
                    z.write(full, "TravelFrog-PC/web/" + rel)
                files += 1
                raw += os.path.getsize(full)
        for dst_name, _src in docs:
            p = os.path.join(STAGE, dst_name)
            z.write(p, "TravelFrog-PC/" + dst_name)

    size = os.path.getsize(OUT)
    log("PC package: %s" % OUT)
    log("  game files : %d (%.1f MB raw)" % (files, raw / 1048576))
    log("  zip size   : %.1f MB  (%.0fs)" % (size / 1048576, time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
