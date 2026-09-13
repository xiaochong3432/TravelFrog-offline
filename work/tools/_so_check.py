import zipfile, sys
def info(p):
    z = zipfile.ZipFile(p)
    so = []
    for i in z.infolist():
        if i.filename.startswith("lib/") and i.filename.endswith(".so"):
            so.append((i.filename, i.compress_type, i.header_offset, i.file_size))
    return z, so
for p in [r"H:\AI\frog\base.apk", r"H:\AI\frog\dist\TravelFrog-offline.apk"]:
    z, so = info(p)
    inf = z.infolist()
    print("==", p)
    print("   total entries:", len(inf))
    for n, ct, off, sz in so:
        # data offset = header_offset + 30 + len(name) + len(extra)
        e = z.getinfo(n)
        hdr = 30 + len(e.filename.encode()) + len(e.extra)
        data = off + hdr
        print(f"   {n:42s} method={ct} dataoff={data} align4096={data%4096} align4={data%4} size={sz}")
    print("   manifest:", "AndroidManifest.xml" in z.namelist())
