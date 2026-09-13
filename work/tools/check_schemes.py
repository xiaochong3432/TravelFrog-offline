#!/usr/bin/env python3
"""Check what signature schemes the repacked APK actually offers, and whether
its core files are byte-identical to the original."""
import zipfile, hashlib, struct

A = r"H:\AI\frog\base.apk"
B = r"H:\AI\frog\dist\TravelFrog-offline.apk"

a = zipfile.ZipFile(A)
b = zipfile.ZipFile(B)

print("--- core files identical? ---")
for n in ["AndroidManifest.xml", "resources.arsc", "classes.dex", "classes2.dex",
          "classes3.dex", "assets/nearme.apk"]:
    try:
        ha = hashlib.md5(a.read(n)).hexdigest()
        hb = hashlib.md5(b.read(n)).hexdigest()
        print(f"  {n:<26} {'SAME' if ha == hb else 'DIFFERENT'}")
    except KeyError as e:
        print(f"  {n:<26} missing: {e}")

print("\n--- META-INF entries in the repacked APK ---")
found = [n for n in b.namelist() if n.upper().startswith("META-INF/")]
if not found:
    print("  (none)")
for n in found:
    print("   ", n)

print("\n--- signature scheme summary ---")
has_v1 = any(n.upper().endswith((".SF", ".RSA", ".DSA", ".EC")) for n in found)
print(f"  v1 (JAR) files present : {has_v1}")
d = open(B, "rb").read()
eocd = d.rfind(b"PK\x05\x06")
cd_off = struct.unpack_from("<I", d, eocd + 16)[0]
trailer = struct.unpack_from("<Q", d, cd_off - 8)[0]
print(f"  v2 signing block       : present, {trailer + 16} bytes before CD")

print("\n--- original local-header extra fields ---")
cnt = 0
with open(A, "rb") as f:
    for i in a.infolist():
        f.seek(i.header_offset)
        hdr = f.read(30)
        nlen, elen = struct.unpack_from("<HH", hdr, 26)
        if elen:
            cnt += 1
print(f"  {cnt} / {len(a.infolist())} original entries had a non-empty extra field")

a.close()
b.close()
