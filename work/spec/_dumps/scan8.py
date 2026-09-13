#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re
JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for k in ["backImage", "frontImage", "frogPose", "travelerPose", "PictureDB", "ResourcesDB", "getPicturePath", "formatPathImage"]:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s (%d) %s" % (k, len(hits), hits[:12]))
    for h in hits[:3]:
        print("     @%d %s" % (h, d[max(0, h - 200):h + 200]))
