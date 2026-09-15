#!/usr/bin/env python3
"""Print a raw slice of a file by character offset -- the companion to jsfind.py
when the interesting code sits BEFORE the anchor you matched."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import argparse
import sys

ap = argparse.ArgumentParser()
ap.add_argument("start", type=int)
ap.add_argument("end", type=int)
ap.add_argument("--file", default=str(PROJECT_ROOT) + "/work/run/web/js/main.min.js")
args = ap.parse_args()

with open(args.file, encoding="utf-8", errors="replace") as fh:
    s = fh.read()
sys.stdout.write(s[args.start:args.end])
sys.stdout.write("\n")
