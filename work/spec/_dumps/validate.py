#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import io
s = io.open(str(PROJECT_ROOT) + "/work/spec/travel-album.md", encoding="utf8").read()
fence = chr(96) * 3
n = s.count(fence)
print("fences:", n, "balanced" if n % 2 == 0 else "UNBALANCED")
print("lines:", len(s.splitlines()))
for l in s.splitlines():
    if l.startswith("#"):
        print(l)
