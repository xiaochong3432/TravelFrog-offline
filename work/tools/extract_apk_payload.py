#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract assets/game/** out of a built APK so the shipped bytes can be booted and probed.

Usage: python tools/extract_apk_payload.py <apk> <dest-dir>
"""
import os
import shutil
import sys
import zipfile


def main():
    apk, dest = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    n = 0
    with zipfile.ZipFile(apk) as z:
        for name in z.namelist():
            if not name.startswith("assets/game/") or name.endswith("/"):
                continue
            rel = name[len("assets/game/"):]
            out = os.path.join(dest, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with z.open(name) as fh, open(out, "wb") as w:
                w.write(fh.read())
            n += 1
    print("extracted %d files to %s" % (n, dest))
    return 0


sys.exit(main())
