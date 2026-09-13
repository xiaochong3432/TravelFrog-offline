#!/usr/bin/env python3
"""Which .eab bundle holds the DATA TABLES, and can we rewrite them?

The 1.0.21 delta ships updated tables (Item / Collection / Picture / Achieve /
museumData / furniture* / TravelData / Cooking). Merging them into our tree needs
to know where the client actually reads them from:
  * a plaintext .eab  -> we can repack it
  * an encrypted .eab -> we cannot (config.eab's magic differs from its 21 siblings)
  * a loose JSON file -> trivial
Also reports which of the 1.0.21 files are art (easily merged) vs tables.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os
import sys

ROOT = str(PROJECT_ROOT) + "/work"
EAB = os.path.join(ROOT, "run", "web", "resource", "China", "eab")
sys.path.insert(0, os.path.join(ROOT, "tools"))

# reuse the repo's reader
import importlib.util
spec = importlib.util.spec_from_file_location("eabl", os.path.join(ROOT, "tools", "eab_list.py"))
eabl = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(eabl)
except SystemExit:
    pass

TABLES = ["museumData", "Item", "Collection", "Picture", "Achieve", "PictureTag",
          "PictureBack", "PictureChara", "furnitureData", "furnitureShopData",
          "furnitureCommon", "Cooking", "cookingData", "Area", "Node", "NodeEdge",
          "NodeItem", "NodeGoal", "NodeConnect", "default.res", "shopData", "Character"]

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


say("=== .eab bundles present ===")
for name in sorted(os.listdir(EAB)):
    p = os.path.join(EAB, name)
    if not name.endswith(".eab"):
        continue
    magic = open(p, "rb").read(8)
    say("  %-16s %9d  magic=%s" % (name, os.path.getsize(p), magic.hex()))

say()
say("=== which bundle contains each table? (index scan of every PLAINTEXT .eab) ===")
found = {}
for name in sorted(os.listdir(EAB)):
    p = os.path.join(EAB, name)
    if not name.endswith(".eab"):
        continue
    head = open(p, "rb").read(8)
    if head[6:7] != b"\x1a":
        say("  %-16s SKIPPED (header flag %s -- not the plaintext variant)"
            % (name, head[6:7].hex()))
        continue
    data = open(p, "rb").read()
    # magic is 8 bytes: 89 45 41 42 0d 0a 1a 0a -- so the u32 index length starts at
    # offset 8 and the JSON index at offset 12 (header = 12 + index length).
    idx_len = int.from_bytes(data[8:12], "little")
    try:
        idx = json.loads(data[12:12 + idx_len].decode("utf-8"))
    except Exception as e:
        say("  %-16s index unreadable: %s" % (name, e))
        continue
    names = [e.get("n") for e in idx]
    for t in TABLES:
        for n in names:
            if n and (n == t or n == t + "_json" or n.startswith(t + ".")):
                found.setdefault(t, []).append(name)

for t in TABLES:
    say("  %-20s %s" % (t, found.get(t, "NOT IN ANY PLAINTEXT BUNDLE")))

say()
say("=== the 1.0.21 delta files (band 1019_1020 + 1020_1021) ===")
for band in ("1019_1020", "1020_1021"):
    d = os.path.join(ROOT, "cdn", "live", band)
    if not os.path.isdir(d):
        continue
    say("-- %s" % band)
    for dp, dn, fn in os.walk(d):
        for f in sorted(fn):
            p = os.path.join(dp, f)
            say("   %-8s %9d  %s" % (os.path.splitext(f)[1] or "(none)",
                                     os.path.getsize(p),
                                     os.path.relpath(p, d)))

sys.stdout = io.open(os.path.join(ROOT, "logs", "table_home.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/table_home.txt (%d chars)" % len(out.getvalue()))
