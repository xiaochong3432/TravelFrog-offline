#!/usr/bin/env python3
"""Quantify the client's protocol handler surface vs the request table."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, collections, os

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
data = open(JS, "rb").read().decode("utf8", "replace")

# request table (from earlier extraction)
ENTRY = re.compile(r'([A-Za-z_][A-Za-z0-9_]{2,40})\s*:\s*\[\[([^\]]*)\]\s*,\s*!(0|1)\s*\]')
req_cmds = [m.group(1) for m in ENTRY.finditer(data)]

# response handlers: prototype methods named like a command
handlers = collections.Counter(re.findall(r'prototype\.([a-z][a-z0-9_]{3,40})=function', data))
handler_names = set(handlers)

# notify_/server push style handlers
notify = sorted(h for h in handler_names if h.startswith(("notify_", "server_", "push_", "on_")))
print(f"request-table commands        : {len(set(req_cmds))}")
print(f"prototype methods total       : {len(handler_names)}")
print(f"commands WITH a client handler: {len(set(req_cmds) & handler_names)}")
missing = sorted(set(req_cmds) - handler_names)
print(f"commands WITHOUT handler      : {len(missing)}")

print(f"\nnotify_/server_/push_ handlers: {len(notify)}")
for n in notify:
    print("   ", n)

print("\n--- missing handlers (sample) ---")
for m in missing[:60]:
    print("   ", m)

# how many handler names look like game commands
cmdish = sorted(h for h in handler_names if re.match(r'^(client|item|travel|album|guest|mail|task|story|rank|visit|lottery|pray|museum|party|spring|greet|furniture|cooking|capsule|calendar|clover|annual|share|misc|hall|recharge|adsmgr|other|koto|animpicture|encyclopedia|wishingpool)_', h))
print(f"\ntotal command-shaped handlers  : {len(cmdish)}")
print("sample:", ", ".join(cmdish[:40]))
