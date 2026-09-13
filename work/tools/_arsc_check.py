import zipfile
for p in [r"H:\AI\frog\base.apk", r"H:\AI\frog\dist\TravelFrog-offline.apk"]:
    z = zipfile.ZipFile(p)
    print("==", p)
    inf = z.infolist()
    # count 4-byte alignment violations for STORED entries
    viol = []
    for e in inf:
        hdr = 30 + len(e.filename.encode("utf-8")) + len(e.extra)
        off = e.header_offset + hdr
        if e.compress_type == 0 and off % 4 != 0:
            viol.append((e.filename, off % 4))
    print("  STORED entries not 4-byte aligned:", len(viol))
    for n, r in viol[:10]:
        print("    ", n, "mod4 =", r)
    for target in ["resources.arsc", "AndroidManifest.xml"]:
        e = z.getinfo(target)
        hdr = 30 + len(e.filename.encode("utf-8")) + len(e.extra)
        off = e.header_offset + hdr
        print(f"  {target}: method={e.compress_type} dataoff={off} mod4={off%4} extra={len(e.extra)}B size={e.file_size}")
