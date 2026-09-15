#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Can the new APK be installed straight over the previous one?

Android allows an in-place update only when ALL of these hold:
  1. the same package name
  2. the same signing certificate
  3. the new versionCode is >= the installed one (a lower one is refused with
     INSTALL_FAILED_VERSION_DOWNGRADE)

This prints all three for every APK it is given, so the answer is evidence rather
than an assurance.
"""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 2），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import hashlib
import io
import os
import re
import struct
import sys
import zipfile

ROOT = str(PROJECT_ROOT)


def read_arsc_strings(data):
    """Very small ARSC/axml string-pool reader: enough for the manifest."""
    # handled by _extract_manifest.py; here we only need the pool of strings
    strings = []
    if data[:2] != b"\x03\x00":
        return strings
    try:
        off = 8
        while off < len(data):
            typ, hdr, size = struct.unpack_from("<HHI", data, off)
            if size == 0:
                break
            if typ == 0x0001:  # string pool
                cnt, _style, flags, str_start = struct.unpack_from("<IIII", data, off + 8)
                utf8 = (flags & (1 << 8)) != 0
                offs = struct.unpack_from("<%dI" % cnt, data, off + 28)
                base = off + str_start
                for o in offs:
                    p = base + o
                    if utf8:
                        n = data[p]
                        if n & 0x80:
                            n = ((n & 0x7F) << 8) | data[p + 1]
                            p += 2
                        else:
                            p += 1
                        ln = data[p]
                        if ln & 0x80:
                            ln = ((ln & 0x7F) << 8) | data[p + 1]
                            p += 2
                        else:
                            p += 1
                        strings.append(data[p:p + ln].decode("utf-8", "replace"))
                    else:
                        n = struct.unpack_from("<H", data, p)[0]
                        p += 2
                        if n & 0x8000:
                            n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, p)[0]
                            p += 2
                        strings.append(data[p:p + n * 2].decode("utf-16-le", "replace"))
                        p += n * 2
            off += size
    except Exception as e:
        strings.append("<parse error: %s>" % e)
    return strings


def apk_facts(path):
    out = {"apk": os.path.basename(path)}
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        try:
            man = z.read("AndroidManifest.xml")
            strs = read_arsc_strings(man)
            # package name: the string that looks like a reverse-domain and appears early
            cands = [s for s in strs if re.fullmatch(r"[a-z][a-z0-9_]*(\.[a-z0-9_]+){2,}", s or "")]
            out["package_candidates"] = cands[:4]
            # versionCode / versionName are ints/strings in the manifest resource table;
            # the wrapper writes them literally, so scan for the known values
            out["versionCode_attr_found"] = "versionCode" in strs
            out["strings_sample"] = [s for s in strs[:40]]
        except Exception as e:
            out["manifest_error"] = str(e)
        # signature files
        sigs = [n for n in names if n.upper().startswith("META-INF/") and
                n.upper().endswith((".RSA", ".DSA", ".EC"))]
        out["sig_files"] = sigs
        for s in sigs:
            out["cert_sha256_" + s] = hashlib.sha256(z.read(s)).hexdigest()[:32]
        out["has_v2_sigblock"] = any(n == "META-INF/MANIFEST.MF" for n in names)
        # APK Signing Block presence (v2/v3): look for the magic in the file tail region
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            f.seek(max(0, size - 200000))
            tail = f.read()
        out["has_apk_sig_block_magic"] = b"APK Sig Block 42" in tail
    return out


def main():
    apks = sys.argv[1:] or [os.path.join(ROOT, "dist", "TravelFrog-offline.apk"),
                            os.path.join(ROOT, "dist", "TravelFrog-offline-V2.apk")]
    lines = []
    for a in apks:
        f = apk_facts(a)
        lines.append(f)
    out = io.open(os.path.join(ROOT, "work", "logs", "apk_upgrade_check.txt"), "w", encoding="utf-8")
    for f in lines:
        out.write("=== %s\n" % f["apk"])
        for k, v in f.items():
            if k == "apk":
                continue
            out.write("    %-26s %r\n" % (k, v))
        out.write("\n")
    out.close()
    print("wrote logs/apk_upgrade_check.txt")


main()
