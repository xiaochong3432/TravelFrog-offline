from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re
raw = open(str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js","rb").read()
for pat in [b"FrogMotionName", b"FrogMotionNum", b"FrogMotionPos", b"FrogMotionStrike", b"getFrogMotion", b"frogMotion", b"FrogPatternMax"]:
    print(f"  {pat.decode():20s} {raw.count(pat)}")
