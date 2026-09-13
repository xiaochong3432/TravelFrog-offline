from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile
z = zipfile.ZipFile(str(PROJECT_ROOT) + "/base.apk")
for i in z.infolist():
    n = i.filename
    if n.startswith("res/") and ("launcher" in n or "icon" in n) and n.endswith(".png"):
        print(f"{i.file_size:>8,}  {n}")
