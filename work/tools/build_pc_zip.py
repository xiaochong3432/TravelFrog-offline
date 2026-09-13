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
import io
import os
import shutil
import sys
import time
import zipfile

ROOT = r"H:\AI\frog"
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
    ("说明书.txt", "说明-先看这个.txt"),
]


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
    for src_name, dst_name in LAUNCHERS:
        src = os.path.join(DIST, src_name)
        if not os.path.isfile(src):
            log("!! missing launcher/doc:", src)
            return 1
        shutil.copy2(src, os.path.join(STAGE, dst_name))
        log("  + %s" % dst_name)

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
        for src_name, dst_name in LAUNCHERS:
            p = os.path.join(STAGE, dst_name)
            z.write(p, "TravelFrog-PC/" + dst_name)

    size = os.path.getsize(OUT)
    log("PC package: %s" % OUT)
    log("  game files : %d (%.1f MB raw)" % (files, raw / 1048576))
    log("  zip size   : %.1f MB  (%.0fs)" % (size / 1048576, time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
