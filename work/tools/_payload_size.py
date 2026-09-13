from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile
z = zipfile.ZipFile(str(PROJECT_ROOT) + "/base.apk")
tot = sum(i.file_size for i in z.infolist() if i.filename.startswith("assets/game/"))
lib = sum(i.file_size for i in z.infolist() if i.filename.startswith("lib/"))
print(f"assets/game uncompressed: {tot/1048576:.1f} MB")
print(f"lib/**        uncompressed: {lib/1048576:.1f} MB")
