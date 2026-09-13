#!/usr/bin/env python3
"""Extract every addProtocolCallback(...) registration, grouped by owning class.

This is the authoritative list of protocol messages the client listens for.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, json

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

# find class boundaries:  var XxxModel=function(e){ ... }(core.Model);
CLASS = re.compile(r'var\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\(')
CALL = re.compile(r'addProtocolCallback\(([^)]*)\)')

starts = [(m.start(), m.group(1)) for m in CLASS.finditer(d)]
def owner(off):
    name = "?"
    for s, n in starts:
        if s <= off:
            name = n
        else:
            break
    return name

groups = {}
for m in CALL.finditer(d):
    args = re.findall(r'"([^"]+)"', m.group(1))
    if not args:
        continue
    groups.setdefault(owner(m.start()), []).extend(args)

total = sorted({a for v in groups.values() for a in v})
print(f"classes registering callbacks: {len(groups)}")
print(f"distinct protocol messages listened for: {len(total)}\n")

for cls, args in sorted(groups.items(), key=lambda kv: -len(kv[1])):
    uniq = sorted(set(args))
    print(f"--- {cls} ({len(uniq)}) ---")
    print("   " + ", ".join(uniq))

json.dump({k: sorted(set(v)) for k, v in groups.items()},
          open(str(PROJECT_ROOT) + "/work/listened_protocols.json", "w", encoding="utf8"),
          ensure_ascii=False, indent=1)
print("\nwrote work/listened_protocols.json")
