#!/usr/bin/env python3
"""Which snapshot of the game are we actually shipping?

The version history the user provided is a public timeline; before comparing
features against it I need to know where OUR package sits on that timeline. The
answer comes from the package itself, not from the APK's versionName alone:

  * base.apk's manifest versionName/versionCode (the client build)
  * manifest.json  -> the H5 bundle's own version
  * version.json   -> hashes; the newest resource sets present tell us how far the
                      asset delivery had got
  * which season*/event bundles exist, and the newest mtimes inside them
"""
import json
import os
import re
import struct
import sys
import zipfile

ROOT = r"H:\AI\frog"
WEB = os.path.join(ROOT, "work", "run", "web")


def axml_strings(data):
    sys.path.insert(0, os.path.join(ROOT, "work", "tools"))
    from axml import parse_string_pool
    (typ, hdr, _size) = struct.unpack_from("<HHI", data, 0)
    off = hdr
    while off < len(data):
        (ctype,) = struct.unpack_from("<H", data, off)
        (chdr, csize) = struct.unpack_from("<HH", data, off + 2)
        if ctype == 0x0001:
            return list(parse_string_pool(data, off)[0])
        if csize == 0:
            break
        off += csize
    return []


print("=== base.apk manifest (the client build) ===")
z = zipfile.ZipFile(os.path.join(ROOT, "base.apk"))
mf = z.read("AndroidManifest.xml")
strs = axml_strings(mf)
for s in strs:
    if re.fullmatch(r"\d+\.\d+\.\d+", s):
        print("   versionName candidate:", s)
for m in re.finditer(rb"versionCode", mf):
    pass
# versionCode/versionName live in the manifest attributes; print the numbers we can see
nums = [s for s in strs if re.fullmatch(r"\d{2,7}", s)]
print("   numeric strings (versionCode and friends):", nums[:12])

print("\n=== H5 bundle ===")
man = json.load(open(os.path.join(WEB, "manifest.json"), encoding="utf-8"))
print("   manifest.json version:", man.get("version"))
print("   initial scripts:", len(man.get("initial", [])), " game scripts:", len(man.get("game", [])))

vj = json.load(open(os.path.join(WEB, "version.json"), encoding="utf-8"))
print("   version.json entries:", len(vj))
print("   sample keys:", list(vj)[:4])

print("\n=== event/season bundles present ===")
eab = os.path.join(WEB, "resource", "China", "eab")
for f in sorted(os.listdir(eab)):
    print("   %-16s %8.1f KB" % (f, os.path.getsize(os.path.join(eab, f)) / 1024))

print("\n=== newest files in the package (delivery watermark) ===")
newest = []
for dp, dn, fn in os.walk(os.path.join(WEB, "resource", "China")):
    for f in fn:
        p = os.path.join(dp, f)
        try:
            newest.append((os.path.getmtime(p), os.path.relpath(p, WEB)))
        except OSError:
            pass
newest.sort(reverse=True)
import time
for t, rel in newest[:8]:
    print("   %s  %s" % (time.strftime("%Y-%m-%d", time.localtime(t)), rel))
