#!/usr/bin/env python3
"""Dump context around a literal / identifier in main.min.js to a UTF-8 file.

Usage:
  jsx.py <outfile> <pattern> [before] [after] [maxhits]

Prints byte offsets and surrounding code (newline-split on ;{}), UTF-8 encoded,
so Chinese stays readable when the output is read as a text file.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, sys

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

out_path = sys.argv[1]
pat = sys.argv[2]

if pat.startswith("@"):  # character-offset range: @start:end
    a, b = pat[1:].split(":")
    seg = d[int(a):int(b)]
    seg = re.sub(r'([;{}])', r'\1\n', seg)
    open(out_path, "w", encoding="utf8").write(f"chars {a}..{b}\n\n" + seg)
    print(f"chars {a}..{b} -> {out_path} ({len(seg)} chars)")
    raise SystemExit(0)
before = int(sys.argv[3]) if len(sys.argv) > 3 else 400
after = int(sys.argv[4]) if len(sys.argv) > 4 else 400
maxhits = int(sys.argv[5]) if len(sys.argv) > 5 else 40

hits = [m.start() for m in re.finditer(pat, d)]
lines = [f"===== {pat!r}  hits={len(hits)} ====="]
for off in hits[:maxhits]:
    seg = d[max(0, off - before):off + after]
    seg = re.sub(r'([;{}])', r'\1\n', seg)
    lines.append(f"\n--- [{off}] ---\n{seg}")
open(out_path, "w", encoding="utf8").write("\n".join(lines))
print(f"{len(hits)} hits -> {out_path}")

if len(sys.argv) > 6 and sys.argv[6] == "--more":
    lines = []
    for name in sys.argv[7:]:
        hits = [m.start() for m in re.finditer(re.escape('"' + name + '"'), d)]
        lines.append(f"\n\n{'#'*90}\n### literal \"{name}\"  hits={len(hits)}\n{'#'*90}")
        for off in hits[:maxhits]:
            seg = d[max(0, off - before):off + after]
            seg = re.sub(r'([;{}])', r'\1\n', seg)
            lines.append(f"\n--- [{off}] ---\n{seg}")
    open(out_path, "a", encoding="utf8").write("\n".join(lines))
    print(f"appended {len(sys.argv)-7} literals -> {out_path}")
