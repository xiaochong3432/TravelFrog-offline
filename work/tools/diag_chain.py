#!/usr/bin/env python3
"""Temporary markers around the syncComplete -> loginCallback chain."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
MAIN = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
d = open(MAIN, encoding="utf8").read()

OLD = "this.setSyncComplete(),this.closeLoginTimeout(),this.slineDownload(),Music.updateBGVolume(),this.loginCallback();break"
NEW = ("this.setSyncComplete(),this.closeLoginTimeout(),"
       "console.log('[offline] syncComplete chain reached'),"
       "this.slineDownload(),Music.updateBGVolume(),"
       "console.log('[offline] invoking loginCallback'),"
       "this.loginCallback(),"
       "console.log('[offline] loginCallback returned');break")

if "[offline] syncComplete chain reached" in d:
    print("markers already present")
elif OLD in d:
    open(MAIN, "w", encoding="utf8").write(d.replace(OLD, NEW))
    print("markers inserted (1 site)")
else:
    print("anchor not found; dumping neighbourhood")
    i = d.find("this.loginCallback()")
    print(repr(d[max(0, i - 320):i + 60]))
