#!/usr/bin/env python3
"""Debug: inspect the entries that fail to read back after repacking."""
import zipfile, struct, zlib, io, sys
sys.path.insert(0, r"H:\AI\frog\work\tools")
import build_apk as B

APK = r"H:\AI\frog\base.apk"
TARGETS = ["META-INF/kotlin-stdlib.kotlin_module", "lib/arm64-v8a/libdc.so",
           "assets/game/index.html", "AndroidManifest.xml"]

z = zipfile.ZipFile(APK)
for name in TARGETS:
    try:
        i = z.getinfo(name)
    except KeyError:
        print(f"{name}: not in original")
        continue
    raw = z.read(name)
    print(f"\n{name}")
    print(f"  compress_type={i.compress_type} flag_bits={i.flag_bits:#06x} "
          f"file_size={i.file_size} compress_size={i.compress_size}")
    print(f"  returned data len={len(raw)}")
    if i.compress_type == 8:
        rc = zlib.compress(raw, 9)
        print(f"  recompressed len={len(rc)}  roundtrip ok={zlib.decompress(rc) == raw}")
    # what does the raw local header say?
    with open(APK, "rb") as f:
        f.seek(i.header_offset)
        hdr = f.read(30)
        (sig, ver, flags, method, t, d, crc, csize, usize, nlen, elen) = struct.unpack("<IHHHHHIIIHH", hdr)
        print(f"  local hdr: sig={sig:#x} ver={ver} flags={flags:#06x} method={method} "
              f"csize={csize} usize={usize} nlen={nlen} elen={elen}")
z.close()

# Now: build a tiny zip with just the failing entry plus a neighbour, and read back
print("\n--- minimal repack test ---")
e = B.read_entries(APK)
pick = [x for x in e if x.name in TARGETS]
data, cd_off, cd_size, eocd = B.write_zip(pick, r"H:\AI\frog\work\_mini.zip")
zz = zipfile.ZipFile(r"H:\AI\frog\work\_mini.zip")
for i in zz.infolist():
    try:
        got = zz.read(i.filename)
        print(f"  OK   {i.filename} ({len(got)} bytes)")
    except Exception as ex:
        print(f"  FAIL {i.filename}: {ex}")
zz.close()
