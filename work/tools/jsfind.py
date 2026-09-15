#!/usr/bin/env python3
"""Context search inside the client bundle.

Written because passing regexes through `pwsh -Command` kept mangling quotes
(that corrupted index.js once already). Usage:

    python tools/jsfind.py CalendarViewControl [CalendarController ...]
    python tools/jsfind.py --file js/main.min.js --win 300 "some regex"

Prints `@offset ...context...` lines, and flags a total hit count per pattern.
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT = os.path.join(ROOT, "run", "web", "js", "main.min.js")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("patterns", nargs="+")
    ap.add_argument("--file", default=DEFAULT)
    ap.add_argument("--win", type=int, default=260)
    ap.add_argument("--max", type=int, default=12, help="max hits printed per pattern")
    ap.add_argument("--count", action="store_true", help="only print hit counts")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8", errors="replace") as fh:
        s = fh.read()

    for pat in args.patterns:
        rx = re.compile(pat)
        hits = list(rx.finditer(s))
        print("=" * 20, "%s  (%d hits)" % (pat, len(hits)))
        if args.count:
            continue
        for m in hits[: args.max]:
            a = max(0, m.start() - args.win)
            b = min(len(s), m.end() + args.win)
            print("@%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
