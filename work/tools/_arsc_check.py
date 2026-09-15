from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile
for p in [str(PROJECT_ROOT) + "/base.apk", str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk"]:
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
