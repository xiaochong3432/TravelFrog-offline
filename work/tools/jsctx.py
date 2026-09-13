#!/usr/bin/env python3
"""Targeted context extraction from minified JS."""
import re, sys, os

def ctx(path, pattern, width=220, limit=25, flags=0):
    data = open(path, "rb").read()
    print(f"\n===== {pattern!r} in {os.path.basename(path)} =====")
    hits = list(re.finditer(pattern, data, flags))
    print(f"({len(hits)} hits)")
    for i, m in enumerate(hits):
        if i >= limit:
            print("  ...more")
            break
        s = max(0, m.start() - width); e = min(len(data), m.end() + width)
        seg = data[s:e].decode("utf8", "replace").replace("\n", " ")
        print(f"[{m.start()}] ...{seg}...\n")

if __name__ == "__main__":
    path = sys.argv[1]
    for pat in sys.argv[2:]:
        ctx(path, pat.encode())
