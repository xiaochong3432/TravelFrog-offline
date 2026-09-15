#!/usr/bin/env python3
"""Move `advanceCraft` and `ownedPictureIds` from module scope into createEngine.

They read `state`, which is a PER-ENGINE variable declared inside createEngine()
(the engine supports several instances in one process), so at module scope they
threw "state is not defined" and every handler that called them returned {} --
i.e. the museum list and the whole 手工 payload silently became empty objects.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re
import sys

ROOT = str(PROJECT_ROOT) + "/work"
P = ROOT + r"\run\engine\index.js"
src = io.open(P, encoding="utf-8").read()

BLOCKS = {
    "advanceCraft": "/* Advance the frog's 手工 work",
    "ownedPictureIds": "/* Every postcard the player owns",
}
ANCHOR = "  /* The client's ItemDB.get() has NO null guard"

moved = []
for name, start_marker in BLOCKS.items():
    start = src.index(start_marker)
    # find the end: the closing brace of the top-level function at column 0
    m = re.compile(r"\n\}\n", re.M).search(src, start)
    assert m, "no end found for %s" % name
    end = m.end()
    block = src[start:end]
    assert "function %s(" % name in block, "block for %s does not contain its function" % name
    src = src[:start] + src[end:]
    moved.append((name, block.rstrip() + "\n"))

anchor = src.index(ANCHOR)
payload = "\n".join(b for _, b in moved) + "\n"
src = src[:anchor] + payload + "\n" + src[anchor:]

io.open(P, "w", encoding="utf-8").write(src)

# verify: both functions must now appear AFTER createEngine's `const state`
state_at = src.index("function createEngine")
for name, _ in moved:
    at = src.index("function %s(" % name)
    print("%-18s now at %d (createEngine at %d) -> %s"
          % (name, at, state_at, "INSIDE" if at > state_at else "STILL OUTSIDE"))
