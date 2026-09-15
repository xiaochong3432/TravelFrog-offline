#!/usr/bin/env python3
"""Which of our `{code:-1}` replies are SILENT in the client?

`MessageModel.getErrorInfo(code)` reads the client's own errcode.json (shipped in
preload.eab). Codes absent from that table return `undefined`, and the call sites
are written as

    var a = MessageModel.getErrorInfo(n.code);
    a && 0 == a.code && (...success...)

so for an unknown code the whole branch is skipped: no message, no state change,
no visible reaction at all. Our engine replies `{code:-1}` in 60+ places, and
errcode.json has no -1 row -- so those paths are exactly the "button does
nothing" defect class the user keeps reporting.

This script reports, per command:
  * does ANY client callback for that command consult getErrorInfo?
  * does our engine ever answer that command with a code the table lacks?
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os
import re
import sys

ROOT = str(PROJECT_ROOT)
WORK = os.path.join(ROOT, "work")
CLIENT = io.open(os.path.join(WORK, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()
ENGINE = io.open(os.path.join(WORK, "run", "engine", "index.js"), encoding="utf-8").read()
ERRCODE = json.load(io.open(os.path.join(WORK, "logs", "errcode_out", "errcode.json"),
                            encoding="utf-8"))
KNOWN = {int(r["code"]) for r in ERRCODE}
DESC = {int(r["code"]): r["desc"] for r in ERRCODE}

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


say("client error table codes: %s" % sorted(KNOWN))
say("engine replies with codes: %s"
    % sorted({int(m.group(1)) for m in re.finditer(r"code:\s*(-?\d+)", ENGINE)}))
say("codes the engine uses that the table LACKS: %s"
    % sorted({int(m.group(1)) for m in re.finditer(r"code:\s*(-?\d+)", ENGINE)} - KNOWN))
say()

# Every send() whose callback body mentions getErrorInfo.
send_re = re.compile(r'send\(\s*"([a-z0-9_]+)"\s*,\s*new\s+core\.Action\d\(')
uses_geterr = {}
for m in send_re.finditer(CLIENT):
    cmd = m.group(1)
    # take a generous window as "the callback body"
    body = CLIENT[m.end():m.end() + 600]
    if "getErrorInfo" in body:
        uses_geterr.setdefault(cmd, []).append(m.start())

say("commands whose callback consults getErrorInfo (%d):" % len(uses_geterr))

# Which commands can our engine answer with a table-unknown code?
# A handler block = `name: (d...) => { ... }` up to the next top-level handler key.
handler_re = re.compile(r"^    ([A-Za-z_][A-Za-z0-9_]*):\s*\(", re.M)
marks = [(m.group(1), m.start()) for m in handler_re.finditer(ENGINE)]
marks.append((None, len(ENGINE)))
risky = []
for i in range(len(marks) - 1):
    name, start = marks[i]
    end = marks[i + 1][1]
    block = ENGINE[start:end]
    bad = sorted({int(x.group(1)) for x in re.finditer(r"code:\s*(-?\d+)", block)} - KNOWN)
    if bad:
        risky.append((name, bad, name in uses_geterr))

for name, bad, silent in sorted(risky, key=lambda r: (not r[2], r[0])):
    say("  %-28s codes=%s  callback-uses-getErrorInfo=%s%s"
        % (name, bad, silent, "   <-- SILENT" if silent else ""))

say()
say("total handler blocks replying with a table-unknown code: %d" % len(risky))
say("of those, callbacks that go through getErrorInfo: %d"
    % sum(1 for r in risky if r[2]))

sys.stdout = open(os.path.join(WORK, "logs", "code_semantics.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/code_semantics.txt")
