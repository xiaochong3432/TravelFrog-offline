from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import struct
def dump(path, label):
    d = open(path, "rb").read()
    eocd = d.rfind(b"PK\x05\x06")
    cd_off = struct.unpack_from("<I", d, eocd + 16)[0]
    print("==", label)
    print("   cd_offset =", cd_off)
    tail = d[cd_off-32:cd_off]
    print("   bytes [cd-32 .. cd):")
    for i in range(0, 32, 8):
        chunk = tail[i:i+8]
        print(f"     -{32-i:2d}: {chunk!r}  as u64={struct.unpack('<Q', chunk)[0] if len(chunk)==8 else '-'}")
    # spec: trailing size at cd-24, magic at cd-16
    spec_size = struct.unpack_from("<Q", d, cd_off - 24)[0]
    spec_start = cd_off - 8 - spec_size
    print("   SPEC read: trailing_size=%d  -> blk_start=%d" % (spec_size, spec_start))
    print("   magic at cd-16 == b'APK Sig Block 42':", d[cd_off-16:cd_off] == b"APK Sig Block 42")
    if 0 <= spec_start <= cd_off:
        lead = struct.unpack_from("<Q", d, spec_start)[0]
        print("   leading size at blk_start =", lead, "match:", lead == spec_size)
        print("   bytes at blk_start:", d[spec_start:spec_start+8])
dump(str(PROJECT_ROOT) + "/base.apk", "ORIGINAL base.apk")
dump(str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk", "OUR BUILD")
