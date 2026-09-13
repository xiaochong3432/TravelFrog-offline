from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile, sys
def info(p):
    z = zipfile.ZipFile(p)
    so = []
    for i in z.infolist():
        if i.filename.startswith("lib/") and i.filename.endswith(".so"):
            so.append((i.filename, i.compress_type, i.header_offset, i.file_size))
    return z, so
for p in [str(PROJECT_ROOT) + "/base.apk", str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk"]:
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
