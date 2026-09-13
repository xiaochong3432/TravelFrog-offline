#!/usr/bin/env python3
"""Dump the login-phase response handlers (client_hello / hall_gen_token / hall_login)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

out = []
i = d.find("t.prototype.client_hello=function")
seg = d[i - 1200:i + 2600]
out.append("===== login-phase handlers (UserModel / NetworkControl) =====")
out.append(re.sub(r'([;{}])', r'\1\n', seg))

j = d.find("client_load_role=function", 210000)
out.append("\n\n===== client_load_role (model side) =====")
out.append(re.sub(r'([;{}])', r'\1\n', d[j:j + 3200]))

txt = "\n".join(out)
open(str(PROJECT_ROOT) + "/work/login_flow.txt", "w", encoding="utf8").write(txt)
print(f"wrote work/login_flow.txt ({len(txt)} chars)")
