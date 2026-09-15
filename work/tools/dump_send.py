#!/usr/bin/env python3
"""Print the SocketManage.send() envelope construction, wrapped for readability."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

d = open(str(PROJECT_ROOT) + "/work/socketmanage.txt", encoding="utf8").read()
i = d.find("t.prototype.send=function")
seg = d[i:i + 2200]
# naive wrap for readability
seg = re.sub(r'([;,{}])', r'\1\n', seg)
open(str(PROJECT_ROOT) + "/work/sm_send.txt", "w", encoding="utf8").write(seg)
print(seg[:2600])
