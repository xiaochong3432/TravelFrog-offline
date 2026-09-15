#!/usr/bin/env python3
"""Dump the class that owns a given prototype method/field.

Usage:
  cls.py <out.txt> <needle> [needle ...] [--max N] [--find]

`needle` may be a method name (looks for `prototype.<needle>=`) or a raw regex.
Prints, for each hit, the owning class body from `var X=function` up to
`__reflect(X.prototype` (or the next class if that is missing).
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, sys

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

args = [a for a in sys.argv[2:] if not a.startswith("--")]
maxlen = 60000
for a in sys.argv[2:]:
    if a.startswith("--max"):
        maxlen = int(a.split("=")[1])


def class_of(off):
    best = None
    for m in re.finditer(r'var\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function', d):
        if m.start() <= off:
            best = (m.start(), m.group(1))
        else:
            break
    return best


out = []
for needle in args:
    pat = r'prototype\.' + re.escape(needle) + r'\s*='
    hits = [m.start() for m in re.finditer(pat, d)]
    if not hits:
        hits = [m.start() for m in re.finditer(needle, d)]
    out.append(f"\n{'#'*90}\n### {needle}  raw-hits={len(hits)}\n{'#'*90}")
    seen = set()
    for off in hits[:6]:
        cl = class_of(off)
        if not cl:
            out.append(f"[{off}] no owning class")
            continue
        start, name = cl
        if name in seen:
            out.append(f"[{off}] (class {name} already dumped)")
            continue
        seen.add(name)
        e = d.find("__reflect(" + name + ".prototype", off)
        if e < 0:
            e = start + maxlen
        body = d[start:min(e + 120, start + maxlen)]
        body = re.sub(r'([;{}])', r'\1\n', body)
        out.append(f"\n===== [{off}] owner {name} (start {start}, len {len(body)}) =====\n{body}")

open(sys.argv[1], "w", encoding="utf8").write("\n".join(out))
print(f"wrote {sys.argv[1]}")
