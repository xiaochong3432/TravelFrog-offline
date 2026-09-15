#!/usr/bin/env python3
"""The authoritative answer: what does the client do with a reply envelope?

Our loopback shim hands `out.reply` to the client's own receive path
(core.Socket -> ReceiveData -> SocketManage -> AnalysisProtocol). Whether a
nonzero `code` reaches the pending Action callback decides the meaning of every
error code we send.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import re
import sys

ROOT = str(PROJECT_ROOT) + "/work"
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()
out = io.StringIO()

for kw in ["AnalysisProtocol", "ReceiveData", "ActionManage.getInstance", "getInstance().getAction"]:
    out.write("=== %s ===\n" % kw)
    hits = list(re.finditer(re.escape(kw), CLIENT))
    out.write("  %d hits\n" % len(hits))
    for m in hits[:3]:
        out.write("  --- @%d\n  %s\n" % (m.start(),
                  CLIENT[max(0, m.start() - 900):m.end() + 900].replace("\n", " ")))
    out.write("\n")

sys.stdout = io.open(os.path.join(ROOT, "logs", "client_recv.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/client_recv.txt")
