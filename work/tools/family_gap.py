#!/usr/bin/env python3
"""Identify each protocol family our engine does NOT implement, from the game's own
data tables -- so the gap list can be named in the game's own words rather than by
command prefix."""
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
GD = json.load(open(os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
ENGINE = open(os.path.join(ROOT, "work", "run", "engine", "index.js"), encoding="utf-8").read()
proto_src = open(os.path.join(ROOT, "work", "run", "engine", "protocol.js"), encoding="utf-8").read()
proto = json.loads(proto_src[proto_src.index("{"):proto_src.rindex("}") + 1])
implemented = set(re.findall(r"^    ([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\(", ENGINE, re.M))

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


missing = sorted(c for c in proto if c not in implemented)
fam = {}
for c in missing:
    fam.setdefault(c.split("_")[0], []).append(c)

T = GD.get("tables", {})

say("=== every command our engine does NOT implement (%d of %d) ===" % (len(missing), len(proto)))
for f in sorted(fam):
    say("%-12s %d : %s" % (f, len(fam[f]), ", ".join(fam[f])))

say()
say("=== names taken from the game's own tables ===")


def names_of(table, limit=6, key="name"):
    t = T.get(table)
    got = []
    if isinstance(t, dict):
        items = t.items()
    elif isinstance(t, list):
        items = list(enumerate(t))
    else:
        return []
    for k, row in items:
        if isinstance(row, dict):
            v = row.get(key) or row.get("title") or row.get("desc") or row.get("info")
            if isinstance(v, str) and v:
                got.append(v)
        elif isinstance(row, str) and row:
            got.append(row)
        if len(got) >= limit:
            break
    return got


for f in sorted(fam):
    say("[%s]" % f)
    for cand in (f + "Data", f + "Common", f + "CommonData", f + "Desc", f + "Page",
                 f, f.capitalize(), f + "TaskData"):
        if cand in T:
            n = names_of(cand)
            if n:
                say("    %-18s -> %s" % (cand, " | ".join(n[:5])))
    # any other table whose key starts with the family name
    for k in sorted(T):
        if k.lower().startswith(f) and k not in (f + "Data", f + "Common", f + "CommonData"):
            n = names_of(k)
            if n:
                say("    %-18s -> %s" % (k, " | ".join(n[:5])))

say()
say("=== is the family's event window OPEN in our engine? ===")
# every stub that closes a window looks like `end_time: 0` in a handler of that family
for f in sorted(fam):
    hits = re.findall(r"^\s{4}(%s_[a-z_]+):.*$" % f, ENGINE, re.M)
    say("  %-12s handlers present: %s" % (f, ", ".join(hits) or "NONE"))

say()
say("=== do the asset bundles for those families exist? ===")
WEB = os.path.join(ROOT, "work", "run", "web", "resource", "China")
for f in sorted(fam):
    found = []
    for dp, dn, fn in os.walk(WEB):
        for x in fn:
            if f.lower() in x.lower():
                found.append(os.path.relpath(os.path.join(dp, x), WEB))
    say("  %-12s %d assets%s" % (f, len(found), ("  e.g. " + ", ".join(found[:3])) if found else ""))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "family_gap.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/family_gap.txt (%d chars)" % len(out.getvalue()))
