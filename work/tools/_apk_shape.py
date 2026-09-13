from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile
z = zipfile.ZipFile(str(PROJECT_ROOT) + "/base.apk")
for n in z.namelist():
    if n.endswith(".dex") or (n.startswith("assets/") and not n.startswith("assets/game/")) or n.endswith(".so") and n.count("/")==1:
        print(f"{z.getinfo(n).file_size:>12,}  {n}")
