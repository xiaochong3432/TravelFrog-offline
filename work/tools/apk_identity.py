#!/usr/bin/env python3
"""Prove the shipped APK carries EXACTLY the build that was verified, AND that it
is the clean wrapper shell rather than a repack of the original channel APK.

Payload identity alone does not catch the mistake that actually shipped: building
with `build_apk.py` (which repacks base.apk, keeping its Application class, its
channel SDKs and its native libraries) instead of `build_wrapper_apk.py` (the
clean WebView shell). Both contain identical assets/game/** -- so a payload-only
check passes -- but the repack HANGS FOREVER on the channel login screen
("移动服务 / 登录中"). The structural assertions below make that unshippable.

    python tools/apk_identity.py
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import argparse
import hashlib
import os
import sys
import zipfile

APK = str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk"
WEB = str(PROJECT_ROOT) + "/work/run/web"

# the files that carry the offline behaviour
CHECK = [
    "index.html",
    "__offline-engine.js",
    "__probe.js",
    "js/main.min.js",
    "js/default.thm.js",
    "resource/China/default.res.json",
]


def sha(b):
    return hashlib.sha256(b).hexdigest()


EXPECT_PACKAGE = "com.frog.offline"
# AndroidManifest.xml, resources.arsc, ic_launcher.png, classes.dex. Signature
# files (META-INF/**) are added by apksigner afterwards and are NOT payload, so
# they are excluded from the count -- counting them made this check fail on a
# perfectly good build.
MAX_PAYLOAD_ENTRIES = 6
MAX_DEX_BYTES = 200 * 1024       # the wrapper's dex is ~19 KB; a repack's is megabytes

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from axml import parse_string_pool      # noqa: E402
except Exception:                            # pragma: no cover
    parse_string_pool = None


def axml_strings(data):
    """All strings in a binary AndroidManifest, via the real AXML string pool.

    A plain substring search for "com.frog.offline" FAILS because the pool stores
    UTF-16: I first "found" that the manifest did not declare our package on an APK
    that was perfectly fine. Parse the pool the way axml.py does -- walk the chunks
    and take the one whose type is 0x0001 -- rather than guessing an offset, and
    note that parse_string_pool returns (strings, header_size, size), not a list.
    """
    if parse_string_pool is None:
        return []
    import struct
    try:
        (typ, hdr_size, _size) = struct.unpack_from("<HHI", data, 0)
        off = hdr_size
        while off < len(data):
            (ctype,) = struct.unpack_from("<H", data, off)
            (chdr, csize) = struct.unpack_from("<HH", data, off + 2)
            if ctype == 0x0001:
                got = parse_string_pool(data, off)
                return list(got[0]) if got and got[0] else []
            if csize == 0:
                break
            off += csize
    except Exception:
        return []
    return []


def check_shape(z, names):
    """Assert the APK is the clean wrapper shell, not a repack of base.apk."""
    bad = []
    print("\n-- shape (must be the clean wrapper, not a base.apk repack) --")

    payload = sorted(n for n in names
                     if not n.startswith("assets/game/") and not n.startswith("META-INF/"))
    print("  payload entries  : %d -> %s" % (len(payload), ", ".join(payload[:10])))
    if len(payload) > MAX_PAYLOAD_ENTRIES:
        bad.append("too many payload entries (%d): this is a repack of base.apk, "
                   "which hangs on the channel-login screen" % len(payload))

    libs = [n for n in names if n.startswith("lib/")]
    print("  native libraries : %d" % len(libs))
    if libs:
        bad.append("contains lib/** native libraries -- that is base.apk's shell")

    other_dex = sorted(n for n in names if n.startswith("classes") and n != "classes.dex")
    if other_dex:
        print("  extra dex        : %s" % ", ".join(other_dex[:6]))
        bad.append("contains %s -- the wrapper has a single classes.dex" % other_dex[:3])
    if "classes.dex" in names:
        n = z.getinfo("classes.dex").file_size
        print("  classes.dex      : %d bytes" % n)
        if n > MAX_DEX_BYTES:
            bad.append("classes.dex is %d bytes (> %d): far more code than the "
                       "wrapper's MainActivity/AssetServer" % (n, MAX_DEX_BYTES))

    assets = [n for n in names if n.startswith("assets/") and not n.startswith("assets/game/")]
    if assets:
        print("  other assets     : %s" % ", ".join(assets[:6]))
        bad.append("extra assets payload: %s" % assets[:3])

    if "AndroidManifest.xml" in names:
        mf = z.read("AndroidManifest.xml")
        strs = axml_strings(mf)
        print("  manifest strings : %d" % len(strs))
        has = EXPECT_PACKAGE in strs
        print("  manifest package : %s" % (EXPECT_PACKAGE if has
                                           else "*** NOT " + EXPECT_PACKAGE + " ***"))
        if not has:
            bad.append("manifest does not declare %s" % EXPECT_PACKAGE)
        joined = " ".join(strs)
        for marker in ("com.ali.croak", "com.oppo", "gosdk", "nearme"):
            if marker in joined:
                print("  !! manifest still references %s" % marker)
                bad.append("manifest still references the original channel (%s)" % marker)
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", default=APK)
    args = ap.parse_args()
    apk = args.apk
    if not os.path.isfile(apk):
        print("missing %s" % apk)
        return 1
    z = zipfile.ZipFile(apk)
    names = set(z.namelist())
    bad = []
    print("APK: %s (%.1f MB)" % (apk, os.path.getsize(apk) / 1048576))
    for rel in CHECK:
        entry = "assets/game/" + rel
        local = os.path.join(WEB, rel.replace("/", os.sep))
        if entry not in names:
            print("  MISSING in apk : %s" % entry)
            bad.append("missing in apk: " + entry)
            continue
        in_apk = z.read(entry)
        if not os.path.isfile(local):
            print("  MISSING on disk: %s" % local)
            bad.append("missing on disk: " + rel)
            continue
        with open(local, "rb") as fh:
            on_disk = fh.read()
        same = sha(in_apk) == sha(on_disk)
        if not same:
            bad.append("differs from the working tree: " + rel)
        print("  %-38s %s  apk=%d disk=%d" % (rel, "IDENTICAL" if same else "*** DIFFERS ***",
                                              len(in_apk), len(on_disk)))

    # every file in the working tree must be in the APK (the game assets).
    # The builders deliberately exclude their dev-only harness, so honour the SAME
    # list here -- otherwise this reports a false problem every run.
    EXCLUDE_SUFFIX = (".clean", ".orig", ".bak")
    EXCLUDE_NAMES = {"__captest.html"}
    missing = []
    count = 0
    for dp, _dn, fn in os.walk(WEB):
        for f in fn:
            if f.endswith(EXCLUDE_SUFFIX) or f in EXCLUDE_NAMES:
                continue
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, WEB).replace(os.sep, "/")
            count += 1
            if "assets/game/" + rel not in names:
                missing.append(rel)
    print("\n  working-tree files: %d, absent from the APK: %d" % (count, len(missing)))
    for m in missing[:10]:
        print("     - %s" % m)
    if missing:
        bad.append("%d working-tree file(s) missing from the APK" % len(missing))

    bad += check_shape(z, names)

    print("\nRESULT: %s" % ("OK - the APK is the verified clean wrapper build"
                            if not bad else "%d problem(s):" % len(bad)))
    for b in bad:
        print("   !! %s" % b)
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
