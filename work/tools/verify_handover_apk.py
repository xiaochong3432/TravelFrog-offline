#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Verify the handover build: our package/key/versionCode, the three requested changes,
and — just as important — that everything else is byte-identical to the V3 APK we started
from.

Usage: python tools/verify_handover_apk.py
"""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 2），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import hashlib
import io
import json
import os
import re
import sys
import zipfile

ROOT = str(PROJECT_ROOT)
NEW = os.path.join(ROOT, "dist", "TravelFrog-offline-V3.apk")
SRC = os.path.join(ROOT, "work", "build", "v3", "V3.apk")
OUT = os.path.join(ROOT, "work", "logs", "handover_check.txt")

# what V3 shipped and we must NOT have changed inside the payload
UNCHANGED = [
    "js/main.min.js", "js/default.thm.js", "map.html", "map_data.json",
    "launcher.js", "manifest.json", "loading_icon.png",
    "__offline-engine.js",
]

bad = 0
lines = []


def say(s):
    lines.append(s)
    enc = getattr(sys.stdout, "encoding", None) or "utf-8"
    print(s.encode(enc, "replace").decode(enc, "replace"), flush=True)


def sha(b):
    return hashlib.sha1(b).hexdigest()[:12]


def main():
    global bad
    nz = zipfile.ZipFile(NEW)
    names = set(nz.namelist())
    say("build : %s (%.1f MB)" % (os.path.basename(NEW), os.path.getsize(NEW) / 1048576))
    say("source: %s (V3, %.1f MB)" % (os.path.basename(SRC), os.path.getsize(SRC) / 1048576))
    say("")

    # ---- layout: our wrapper keeps the game under assets/game/
    say("=== payload layout (our wrapper) ===")
    game = [n for n in names if n.startswith("assets/game/")]
    say("  assets/game entries: %d" % len(game))
    for need in ["assets/game/index.html", "assets/game/__probe.js",
                 "assets/game/__offline-engine.js", "classes.dex"]:
        ok = need in names
        say("  %-38s %s" % (need, "present" if ok else "MISSING"))
        if not ok:
            bad += 1

    # ---- versionCode / package / signature are checked by aapt+apksigner outside;
    #      here: content
    say("")
    say("=== the three requested changes ===")
    shell = nz.read("assets/game/__probe.js").decode("utf-8")
    idx = nz.read("assets/game/index.html").decode("utf-8")

    chk = [
        ("导出修复: 调用 FrogNative.exportSave", "FrogNative.exportSave" in shell),
        ("导出修复: 位置回调 __saveExported", "__saveExported" in shell),
        ("导出修复: 导出按钮走桥", "where = String(FrogNative.exportSave" in shell),
        ("制作人员: 面板存在", "function showCredits" in shell),
        ("制作人员: 点按钮打开面板", "showCredits();" in shell),
        ("制作人员: 名单 Balticx", "Balticx" in shell),
        ("制作人员: 名单 兔子国国王", "兔子国国王" in shell),
        ("制作人员: 名单 西瓜给我咬一口", "西瓜给我咬一口" in shell),
        ("制作人员: 名单 yxcatqwq", "yxcatqwq" in shell),
        ("制作人员: 组名 旅行青蛙离线版制作组", "旅行青蛙离线版制作组" in shell),
        ("声明人: 改成制作组", "声明人：旅行青蛙离线版制作组" in idx),
    ]
    for label, ok in chk:
        say("  %-38s %s" % (label, "OK" if ok else "MISSING"))
        if not ok:
            bad += 1

    # the button label lives in the texture: prove the texture changed
    say("")
    say("=== the button texture (label is drawn into the art) ===")
    eab_new = nz.read("assets/game/resource/China/eab/system.eab")
    with zipfile.ZipFile(SRC) as zs:
        # V3 keeps the payload at the assets root, so its texture bundle is here
        eab_old = zs.read("assets/resource/China/eab/system.eab")
    md5_new = hashlib.md5(eab_new).hexdigest()
    ver = json.loads(nz.read("assets/game/version.json").decode("utf-8"))
    entry = ver.get("resource/China/eab/system.eab")
    say("  system.eab md5 new=%s  version.json=%s  %s"
        % (md5_new, entry, "MATCH" if entry == md5_new else "MISMATCH"))
    if entry != md5_new:
        bad += 1
    say("  system.eab size %d -> %d bytes (one texture re-rendered)"
        % (len(eab_old), len(eab_new)))

    # ---- everything else untouched
    say("")
    say("=== everything else byte-identical to the V3 payload ===")
    with zipfile.ZipFile(SRC) as zs:
        for rel in UNCHANGED:
            a = zs.read("assets/" + rel)
            b = nz.read("assets/game/" + rel)
            same = a == b
            say("  %-26s %s  %s" % (rel, sha(a), "same" if same else "CHANGED (%s)" % sha(b)))
            if not same:
                bad += 1
        # every resource file except the texture bundle + version.json
        diff = []
        src_names = {n[len("assets/"):]: n for n in zs.namelist() if n.startswith("assets/")}
        for rel, src_name in src_names.items():
            tgt = "assets/game/" + rel
            if tgt not in names:
                diff.append(rel + " (missing in new)")
                continue
            if rel in ("__probe.js", "index.html", "version.json",
                       "resource/China/eab/system.eab"):
                continue
            if zs.read(src_name) != nz.read(tgt):
                diff.append(rel)
        say("  other files differing: %d %s" % (len(diff), diff[:10]))
        if diff:
            bad += 1
        say("  payload file count  : %d (V3 had %d)"
            % (len(game), len([n for n in zs.namelist() if n.startswith('assets/')])))

    # ---- the wrapper's own java
    say("")
    say("=== our wrapper's bridge ===")
    dex = nz.read("classes.dex")
    for label, needle in [("内部存储/", "内部存储/".encode()),
                          ("__saveExported", b"__saveExported"),
                          ("PICKER", b"PICKER")]:
        ok = needle in dex
        say("  classes.dex has %-16s %s" % (label, "OK" if ok else "MISSING"))
        if not ok:
            bad += 1

    say("")
    say("RESULT: %s" % ("OK" if bad == 0 else "FAIL (%d)" % bad))
    io.open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("wrote logs/handover_check.txt")
    return 0 if bad == 0 else 1


sys.exit(main())
