#!/usr/bin/env python3
"""Inspect base.apk zip layout: compression per entry, alignment of .so, EOCD info.

Repacking must preserve STORED/alignment for anything the loader maps directly.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile, struct, os, collections

APK = str(PROJECT_ROOT) + "/base.apk"

z = zipfile.ZipFile(APK)
print(f"entries: {len(z.infolist())}")

methods = collections.Counter()
for i in z.infolist():
    methods[i.compress_type] += 1
print("compress_type counts:", dict(methods), " (0=STORED, 8=DEFLATED)")

print("\n--- lib/*.so entries ---")
for i in z.infolist():
    if i.filename.endswith(".so"):
        print(f"  {i.filename:<52} method={i.compress_type} size={i.file_size} "
              f"csize={i.compress_size} offset={i.header_offset}")

print("\n--- alignment check for STORED entries ---")
bad = 0
checked = 0
with open(APK, "rb") as f:
    for i in z.infolist():
        if i.compress_type != 0:
            continue
        checked += 1
        f.seek(i.header_offset)
        hdr = f.read(30)
        nlen, elen = struct.unpack_from("<HH", hdr, 26)
        data_off = i.header_offset + 30 + nlen + elen
        if data_off % 4 != 0:
            bad += 1
            if bad <= 5:
                print(f"  NOT 4-byte aligned: {i.filename} data@{data_off} (mod4={data_off % 4})")
print(f"  STORED entries checked={checked}, not 4-aligned={bad}")

print("\n--- assets/game sample entries ---")
n = 0
for i in z.infolist():
    if i.filename.startswith("assets/game/") and n < 5:
        print(f"  {i.filename:<60} method={i.compress_type} size={i.file_size}")
        n += 1

print("\n--- META-INF (existing signatures) ---")
for i in z.infolist():
    if i.filename.upper().startswith("META-INF/"):
        print(f"  {i.filename}  {i.file_size}")
z.close()
