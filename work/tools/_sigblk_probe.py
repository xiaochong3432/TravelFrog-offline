from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import struct
d = open(str(PROJECT_ROOT) + "/base.apk","rb").read()
i = d.rfind(b"PK\x05\x06")
cd_off = struct.unpack_from("<I", d, i+16)[0]
print("cd_offset", cd_off)
print("16 bytes before cd:", d[cd_off-16:cd_off])
print("has APK Sig Block 42 magic:", d[cd_off-16:cd_off] == b"APK Sig Block 42")
