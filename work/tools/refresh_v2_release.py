#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Refresh the V2 release artifacts with the current tree.

The V2 release (built 09-13) predates the 导出存档 fix, so:
  * dist/TravelFrog-PC.zip                     rebuilt from work/run/web
  * dist/TravelFrog-PC（解压后按照说明打开即玩）-V2.zip   same bytes, release name
  * dist/TravelFrog-PC（解压后按照说明打开即玩）-V2/      the unpacked copy players may
                                                    use directly -> refreshed in place
  * dist/TravelFrog-offline-V2.apk             today's APK (V2 engine + export fix)

Everything is verified afterwards by hash + content markers, not by "the command ran".
"""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 2），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import hashlib
import io
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = str(PROJECT_ROOT)
DIST = os.path.join(ROOT, "dist")
APK = os.path.join(DIST, "TravelFrog-offline.apk")
APK_V2 = os.path.join(DIST, "TravelFrog-offline-V2.apk")
ZIP = os.path.join(DIST, "TravelFrog-PC.zip")
V2_DIR = os.path.join(DIST, "TravelFrog-PC（解压后按照说明打开即玩）-V2")
V2_ZIP = V2_DIR + ".zip"


def log(*a):
    enc = getattr(sys.stdout, "encoding", None) or "utf-8"
    print(*[str(x).encode(enc, "replace").decode(enc, "replace") for x in a], flush=True)


def sha1(p, n=None):
    h = hashlib.sha1()
    with open(p, "rb") as f:
        if n:
            h.update(f.read(n))
        else:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def main():
    # 1. rebuild the zip from the current tree
    r = subprocess.run([sys.executable, os.path.join(ROOT, "work", "tools", "build_pc_zip.py")],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    log(r.stdout.strip() or r.stderr.strip())
    if r.returncode != 0 or not os.path.isfile(ZIP):
        log("!! zip build failed")
        return 1

    log("zip sha1 %s  %.1f MB" % (sha1(ZIP)[:12], os.path.getsize(ZIP) / 1048576))

    # 2. release name
    shutil.copy2(ZIP, V2_ZIP)
    log("copied -> %s (%.1f MB)" % (os.path.basename(V2_ZIP), os.path.getsize(V2_ZIP) / 1048576))

    # 3. refresh the unpacked copy in place
    with zipfile.ZipFile(ZIP) as z:
        z.extractall(V2_DIR)
    log("refreshed unpacked folder %s" % os.path.basename(V2_DIR))

    # 4. the APK under the V2 name
    shutil.copy2(APK, APK_V2)
    log("copied -> %s (%.1f MB)" % (os.path.basename(APK_V2), os.path.getsize(APK_V2) / 1048576))

    # ---------------------------------------------------------------- verify
    log("")
    log("=== verify ===")
    bad = 0
    tree_shell = os.path.join(ROOT, "work", "run", "web", "__probe.js")
    tree_engine = os.path.join(ROOT, "work", "run", "web", "__offline-engine.js")
    tree_shell_b = open(tree_shell, "rb").read()
    tree_engine_b = open(tree_engine, "rb").read()
    for zip_path in (ZIP, V2_ZIP):
        with zipfile.ZipFile(zip_path) as z:
            names = z.namelist()
            shell = z.read("TravelFrog-PC/web/__probe.js").decode("utf-8")
            engine = z.read("TravelFrog-PC/web/__offline-engine.js").decode("utf-8")
            manual = z.read("TravelFrog-PC/说明-先看这个.txt").decode("utf-8")
            ok = ("FrogNative.exportSave" in shell and "__saveExported" in shell
                  and "wayType" in engine and "旅行青蛙.exe" in "\n".join(names)
                  and "八、V2 之后的修复" in manual)
            log("  %-52s entries=%-5d export-fix+destination+manual: %s"
                % (os.path.basename(zip_path), len(names), "OK" if ok else "MISSING"))
            if not ok:
                bad += 1
            # identical to the tree -- compare BYTES: io.open() translates CRLF and would
            # report a difference that does not exist.
            if z.read("TravelFrog-PC/web/__probe.js") != tree_shell_b:
                log("    !! shell differs from the tree")
                bad += 1
            if z.read("TravelFrog-PC/web/__offline-engine.js") != tree_engine_b:
                log("    !! engine bundle differs from the tree")
                bad += 1

    for apk_path in (APK, APK_V2):
        with zipfile.ZipFile(apk_path) as z:
            dex = z.read("classes.dex")
            shell = z.read("assets/game/__probe.js").decode("utf-8")
            engine = z.read("assets/game/__offline-engine.js").decode("utf-8")
            ok = (b"\xe5\x86\x85\xe9\x83\xa8\xe5\xad\x98\xe5\x82\xa8/" in dex   # 内部存储/
                  and b"__saveExported" in dex
                  and "FrogNative.exportSave" in shell
                  and "wayType" in engine)
            log("  %-52s dex=%-6d export-fix: %s" % (os.path.basename(apk_path), len(dex),
                                                     "OK" if ok else "MISSING"))
            if not ok:
                bad += 1
    if sha1(APK) != sha1(APK_V2):
        log("  !! the two APKs differ")
        bad += 1

    # the unpacked folder must carry the fix too
    up_shell = os.path.join(V2_DIR, "TravelFrog-PC", "web", "__probe.js")
    if os.path.isfile(up_shell):
        t = io.open(up_shell, encoding="utf-8").read()
        ok = "FrogNative.exportSave" in t
        log("  %-52s export-fix: %s" % ("unpacked folder web/__probe.js", "OK" if ok else "MISSING"))
        if not ok:
            bad += 1
    log("")
    log("RESULT: %s" % ("OK" if bad == 0 else "FAIL (%d)" % bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
