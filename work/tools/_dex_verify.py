from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile, re
z = zipfile.ZipFile(str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk")
dex = z.read("classes.dex")
for needle in [b"readMirrorSave", b"mirrorSave", b"18080", b"save-mirror.json", b"frog.local"]:
    print(f"  {needle.decode():20s} {'present' if needle in dex else 'ABSENT'}")
# the fixed-port value is compiled into the bytecode as an int constant; confirm the
# string form is at least referenced via the asset-server log line
print("  asset server log str:", b"asset server on 127.0.0.1:" in dex)
