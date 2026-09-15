#!/usr/bin/env python3
"""Measure EXACTLY which CDN files our build is missing, by md5.

work/cdn/patch.json is the live hotfix CDN's own file list: for every file it
records which patch band changed it, its md5 and its size. Our package is a full
build at v1.0.20, so:

    md5(our copy) == patch.json md5   -> we already have that file's current version
    missing, or md5 differs           -> we do NOT have the CDN's version

Grouping the mismatches by band turns "what are we missing?" from an opinion into a
measurement, and tells us which update bands our snapshot predates.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import collections
import hashlib
import io
import json
import os
import sys
import zipfile

ROOT = str(PROJECT_ROOT)
CDN = os.path.join(ROOT, "work", "cdn")
WEB = os.path.join(ROOT, "work", "run", "web")
APK = os.path.join(ROOT, "base.apk")

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


patch = json.load(open(os.path.join(CDN, "patch.json"), encoding="utf-8"))
files = {k: v for k, v in patch.items() if not k.startswith("__")}

z = zipfile.ZipFile(APK)
apk_names = set(z.namelist())


def md5_of(name):
    """Prefer the APK copy (that is what we ship), fall back to the work tree."""
    entry = "assets/game/" + name
    if entry in apk_names:
        return hashlib.md5(z.read(entry)).hexdigest(), "apk"
    p = os.path.join(WEB, name.replace("/", os.sep))
    if os.path.isfile(p):
        with open(p, "rb") as fh:
            return hashlib.md5(fh.read()).hexdigest(), "work"
    return None, None


have, differ, absent = [], [], []
for name, info in sorted(files.items()):
    want = info.get("1")
    got, src = md5_of(name)
    if got is None:
        absent.append((name, info))
    elif got == want:
        have.append((name, info))
    else:
        differ.append((name, info, src))

say("=== CDN file list vs our build ===")
say("  entries in patch.json      : %d" % len(files))
say("  we have the SAME md5       : %d" % len(have))
say("  we have a DIFFERENT version: %d" % len(differ))
say("  we do not have the file    : %d" % len(absent))

say()
say("=== mismatches by patch band (i.e. which updates we predate) ===")
for label, rows in (("DIFFERENT", differ), ("MISSING", absent)):
    band = collections.Counter(r[1].get("0", "?") for r in rows)
    say("  %s:" % label)
    for b, n in sorted(band.items()):
        say("     %-14s %4d" % (b, n))

say()
say("=== everything we are missing / behind on ===")
def band_key(b):
    import re
    nums = [int(x) for x in re.findall(r"\d+", b or "0")]
    return max(nums) if nums else 0


for name, info, src in sorted(differ, key=lambda r: -band_key(r[1].get("0"))):
    say("  DIFFER  %-14s %-70s our=%s cdn=%s" % (info.get("0"), name, src, info.get("2")))
for name, info in sorted(absent, key=lambda r: -band_key(r[1].get("0"))):
    say("  ABSENT  %-14s %-70s cdn=%s" % (info.get("0"), name, info.get("2")))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "cdn_vs_ours.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/cdn_vs_ours.txt")
print("same=%d differ=%d absent=%d" % (len(have), len(differ), len(absent)))
