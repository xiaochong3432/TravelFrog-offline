#!/usr/bin/env python3
"""Search the minified client bundle for literal patterns and print context.

Usage:
  python tools/jsgrep.py "e.New=" --before 200 --after 900
  python tools/jsgrep.py "GuideName_Step" --limit 3
  python tools/jsgrep.py --file work/run/web/js/main.min.js "pattern"

Exists because passing quoted regexes through PowerShell mangles them; this keeps
the pattern in a Python string read from argv untouched.
Writes to logs/jsgrep.txt and prints the path.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import argparse
import io
import os
import sys

ROOT = str(PROJECT_ROOT) + "/work"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("patterns", nargs="+")
    ap.add_argument("--file", default=os.path.join(ROOT, "run", "web", "js", "main.min.js"))
    ap.add_argument("--before", type=int, default=200)
    ap.add_argument("--after", type=int, default=600)
    ap.add_argument("--limit", type=int, default=2)
    args = ap.parse_args()

    text = io.open(args.file, encoding="utf-8", errors="replace").read()
    out = io.StringIO()
    out.write("file: %s  (%d bytes)\n" % (args.file, len(text)))
    for pat in args.patterns:
        hits = []
        start = 0
        while True:
            i = text.find(pat, start)
            if i < 0:
                break
            hits.append(i)
            start = i + len(pat)
        out.write("\n=== %r : %d hits\n" % (pat, len(hits)))
        for i in hits[:args.limit]:
            a = max(0, i - args.before)
            b = min(len(text), i + len(pat) + args.after)
            out.write("  @%d  ...%s...\n\n" % (i, text[a:b].replace("\n", " ")))
    sys.stdout = io.open(os.path.join(ROOT, "logs", "jsgrep.txt"), "w", encoding="utf-8")
    sys.stdout.write(out.getvalue())
    print("wrote logs/jsgrep.txt (%d chars)" % len(out.getvalue()))


main()
