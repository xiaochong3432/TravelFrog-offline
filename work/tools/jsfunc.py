#!/usr/bin/env python3
"""Dump a whole method body out of the minified client bundle.

Usage:
  python tools/jsfunc.py checkGuide
  python tools/jsfunc.py client_load_role --file work/run/web/js/main.min.js

Finds `prototype.<name>=function` (or `<name>=function` as a fallback) and prints
up to the next `,<ident>.prototype.` boundary, so a multi-KB method can be read in
one go. Also lists every `send("...")` command the body issues -- that is the
"does this step need the server?" question in one line.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import argparse
import io
import os
import re
import sys

ROOT = str(PROJECT_ROOT) + "/work"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--file", default=os.path.join(ROOT, "run", "web", "js", "main.min.js"))
    ap.add_argument("--max", type=int, default=9000)
    args = ap.parse_args()

    text = io.open(args.file, encoding="utf-8", errors="replace").read()
    starts = [m.end() for m in re.finditer(r"prototype\.%s=function" % re.escape(args.name), text)]
    if not starts:
        starts = [m.end() for m in re.finditer(r"[.\s]%s=function" % re.escape(args.name), text)]
    if not starts:
        print("not found: %s" % args.name)
        return

    out = io.StringIO()
    for s in starts[:2]:
        m = re.compile(r",[A-Za-z_$][A-Za-z0-9_$]*\.prototype\.").search(text, s)
        e = m.start() if m else s + args.max
        body = text[s:e]
        if len(body) > args.max:
            body = body[:args.max] + " ...[truncated]"
        cmds = []
        for c in re.finditer(r'send\(\s*"([a-z0-9_]+)"', body):
            if c.group(1) not in cmds:
                cmds.append(c.group(1))
        out.write("=== %s @%d  (%d chars)%s\n" % (args.name, s, len(body),
                  "" if m else "  [no boundary found]"))
        out.write("    sends: %s\n\n" % (cmds or "NONE -- purely client-side"))
        out.write(body.replace("\n", " ") + "\n\n")

    sys.stdout = io.open(os.path.join(ROOT, "logs", "jsfunc.txt"), "w", encoding="utf-8")
    sys.stdout.write(out.getvalue())
    print("wrote logs/jsfand.txt".replace("jsfand", "jsfunc") + " (%d chars)" % len(out.getvalue()))


main()
