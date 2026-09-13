#!/usr/bin/env python3
"""The authoritative answer: what does the client do with a reply envelope?

Our loopback shim hands `out.reply` to the client's own receive path
(core.Socket -> ReceiveData -> SocketManage -> AnalysisProtocol). Whether a
nonzero `code` reaches the pending Action callback decides the meaning of every
error code we send.
"""
import io
import os
import re
import sys

ROOT = r"H:\AI\frog\work"
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
