#!/usr/bin/env python3
"""Compare EVERY table in the 1.0.21 delta against the table our build uses.

If they are already identical, the "merge the updated tables" part of the 1.0.21
work is a no-op and I should say so instead of pretending to merge something.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os
import sys

ROOT = str(PROJECT_ROOT) + "/work"
GD = json.load(open(os.path.join(ROOT, "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
DELTA = os.path.join(ROOT, "cdn", "live")

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


def norm(v):
    return json.dumps(v, sort_keys=True, ensure_ascii=False)


# index every .json in the archive by basename
by_name = {}
for band in sorted(os.listdir(DELTA)):
    for dp, dn, fn in os.walk(os.path.join(DELTA, band)):
        for f in fn:
            if f.endswith(".json"):
                by_name.setdefault(f, []).append(os.path.join(dp, f))

say("=== delta json files and where they sit ===")
for f in sorted(by_name):
    rel = os.path.relpath(by_name[f][0], DELTA)
    say("  %-26s %s" % (f, rel))

say()
say("=== table by table: ours vs the delta ===")
same = diff = absent = 0
for f in sorted(by_name):
    name = f[:-5]
    mine = T.get(name)
    if mine is None:
        absent += 1
        continue
    p = by_name[f][0]
    try:
        theirs = json.load(open(p, encoding="utf-8"))
    except Exception as e:
        say("  %-24s delta unreadable: %s" % (name, e))
        continue
    if norm(mine) == norm(theirs):
        same += 1
        say("  %-24s IDENTICAL (already the 1.0.21 version)" % name)
    else:
        diff += 1
        a = norm(mine)
        b = norm(theirs)
        # find the first difference for a human-readable clue
        i = 0
        while i < min(len(a), len(b)) and a[i] == b[i]:
            i += 1
        say("  %-24s DIFFERS  ours=%d bytes delta=%d bytes  first diff @%d:\n      ours : %s\n      delta: %s"
            % (name, len(a), len(b), i, a[max(0, i - 80):i + 120], b[max(0, i - 80):i + 120]))

say()
say("identical=%d  differs=%d  (delta files with no matching table in our build: %d)"
    % (same, diff, absent))

sys.stdout = io.open(os.path.join(ROOT, "logs", "delta_table_diff.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/delta_table_diff.txt")
