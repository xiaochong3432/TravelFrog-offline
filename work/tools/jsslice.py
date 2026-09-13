#!/usr/bin/env python3
"""Print a raw slice of a file by character offset -- the companion to jsfind.py
when the interesting code sits BEFORE the anchor you matched."""
import argparse
import sys

ap = argparse.ArgumentParser()
ap.add_argument("start", type=int)
ap.add_argument("end", type=int)
ap.add_argument("--file", default=r"H:\AI\frog\work\run\web\js\main.min.js")
args = ap.parse_args()

with open(args.file, encoding="utf-8", errors="replace") as fh:
    s = fh.read()
sys.stdout.write(s[args.start:args.end])
sys.stdout.write("\n")
