#!/usr/bin/env python3
"""How far does OUR snapshot's content actually reach?

The client's versionName is 1.0.20 (2023-12), but resources were updated
server-side afterwards -- and the manifest does list pic_2024/pic_2025. So the
watermark has to be read from the DATA, not from the version number.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os
import re
import sys

ROOT = str(PROJECT_ROOT)
WEB = os.path.join(ROOT, "work", "run", "web")
GD = json.load(open(os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


say("=== furniture whose art name suggests a later set (xw / new) ===")
rows = T.get("furnitureData") or {}
hits = []
for k, r in (rows.items() if isinstance(rows, dict) else enumerate(rows)):
    if not isinstance(r, dict):
        continue
    blob = json.dumps(r, ensure_ascii=False)
    if re.search(r"xw\d|_new|2024|2025", blob):
        hits.append((k, r.get("name"), r.get("id")))
say("  %d rows mention xw/new/2024/2025; sample:" % len(hits))
for h in hits[:10]:
    say("    %s" % (h,))

say()
say("=== the Note/Pic set: which years are covered? ===")
for k in sorted(T):
    if "note" in k.lower() or k in ("Picture",):
        t = T[k]
        rows2 = t if isinstance(t, list) else list(t.values())
        yrs = set()
        for r in rows2:
            b = json.dumps(r, ensure_ascii=False)
            for y in re.findall(r"20\d\d", b):
                yrs.add(y)
        say("  %-16s %4d rows  years seen: %s" % (k, len(rows2), ", ".join(sorted(yrs)) or "—"))

say()
say("=== collection rows added late (highest ids) ===")
coll = T.get("Collection") or []
say("  Collection rows: %d" % len(coll))
for r in coll[-6:]:
    say("    %s" % json.dumps(r, ensure_ascii=False)[:130])

say()
say("=== museum collection ids reference which Collection rows? ===")
md = T.get("museumData") or []
say("  museumData rows: %d" % len(md))
ids = []
for r in md:
    if isinstance(r, dict):
        ids += [s for s in str(r.get("collection_id", "")).split(",") if s]
say("  collection ids referenced: %s" % ", ".join(ids))
by_id = {}
for r in coll:
    if isinstance(r, dict):
        by_id[str(r.get("id"))] = r.get("name")
say("  resolved: %s" % ", ".join("%s=%s" % (i, by_id.get(i, "?")) for i in ids[:12]))

say()
say("=== does the package contain the museum art the client needs? ===")
need = ["bwg_blink", "info_jiangxi", "info_shandong", "info_nanyuewang", "info_wuwenhua"]
for n in need:
    found = [f for dp, dn, fn in os.walk(os.path.join(WEB, "resource", "China"))
             for f in fn if n in f]
    say("  %-18s %d %s" % (n, len(found), found[0].split("China")[-1] if found else "MISSING"))

say()
say("=== Pic_2024 / Pic_2025: are those files really here? ===")
for f in ["pic_2024.png", "pic_2025.png", "pic_20240.png", "pic_20250.png"]:
    found = [os.path.relpath(os.path.join(dp, x), WEB)
             for dp, dn, fn in os.walk(os.path.join(WEB, "resource", "China"))
             for x in fn if x == f]
    say("  %-14s %s" % (f, found[0] if found else "MISSING"))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "watermark.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/watermark.txt")
