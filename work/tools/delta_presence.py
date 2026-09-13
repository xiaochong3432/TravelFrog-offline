#!/usr/bin/env python3
"""Is the 1.0.21 content ALREADY in our tree? (art, tables, rows)

"Merge as needed" only makes sense once we know what is actually missing. This
checks each headline 1.0.21 addition against our own resources and tables:
新博物馆明信片 (BWG_SX1/SX2/WWH1/WWH2) / xw3 家具套 / 山西博物院 / 更新的表.
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
WEBIMG = os.path.join(ROOT, "run", "web", "resource", "China", "images")
GD = json.load(open(os.path.join(ROOT, "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
DELTA = os.path.join(ROOT, "cdn", "live")
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


def art_index():
    idx = {}
    for dp, dn, fn in os.walk(WEBIMG):
        for f in fn:
            idx.setdefault(f.lower(), []).append(os.path.relpath(os.path.join(dp, f), WEBIMG))
    return idx


ART = art_index()
say("=== art: delta files that are MISSING from our tree, by band ===")
missing = []
for band in sorted(os.listdir(DELTA)):
    root = os.path.join(DELTA, band)
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if not f.lower().endswith(".png"):
                continue
            if f.lower() not in ART:
                missing.append((band, f))
by_band = {}
for band, f in missing:
    by_band.setdefault(band, []).append(f)
for band in sorted(by_band):
    say("  %-10s %4d missing, e.g. %s" % (band, len(by_band[band]), ", ".join(sorted(by_band[band])[:8])))
say("  TOTAL delta PNGs missing from our tree: %d" % len(missing))

say()
say("=== the headline 1.0.21 art families ===")
for fam in ["BWG_SX1", "BWG_SX2", "BWG_WWH1", "BWG_WWH2", "bwg_shanxi", "bwg_wuwe",
            "xw3", "back_mainout_2", "u_month4", "courtyard"]:
    hits = sorted(k for k in ART if fam.lower() in k)
    say("  %-16s %3d files in our tree%s" % (fam, len(hits), ("  e.g. " + ", ".join(hits[:4])) if hits else ""))

say()
say("=== xw3 in the furniture tables ===")
for tab in ["furnitureData", "furnitureShopData", "furnitureCommon"]:
    v = T.get(tab)
    rows = v if isinstance(v, list) else list((v or {}).values())
    hit = [r for r in rows if "xw3" in json.dumps(r, ensure_ascii=False).lower()]
    say("  %-20s rows=%-5d mentioning xw3: %d" % (tab, len(rows), len(hit)))
    for r in hit[:3]:
        say("        %s" % json.dumps(r, ensure_ascii=False)[:200])

say()
say("=== the new postcards in our Picture table? ===")
pic = T.get("Picture")
prows = pic if isinstance(pic, list) else list((pic or {}).values())
byid = {}
for r in prows:
    if isinstance(r, dict) and r.get("id") is not None:
        byid[int(r["id"])] = r
for pid in [2109, 2110, 3063, 2115, 2116, 3066, 2119, 2120, 3067]:
    r = byid.get(pid)
    say("  id=%-5s %s  %s" % (pid, "PRESENT" if r else "ABSENT",
                             (r.get("name") if r else "")))

say()
say("=== museum goal tags in GoalNumber (delta has id 100+) ===")
gn = T.get("GoalNumber")
grows = gn if isinstance(gn, list) else list((gn or {}).values())
gids = sorted(int(r["id"]) for r in grows if isinstance(r, dict) and str(r.get("id", "")).isdigit())
say("  ours: %d rows, ids %s ... %s" % (len(gids), gids[:6], gids[-4:]))
say("  ours contains 100+? %s" % [i for i in gids if i >= 100])
dpath = None
for band in os.listdir(DELTA):
    for dp, dn, fn in os.walk(os.path.join(DELTA, band)):
        if "GoalNumber.json" in fn:
            dpath = os.path.join(dp, "GoalNumber.json")
if dpath:
    theirs = json.load(open(dpath, encoding="utf-8"))
    trows = theirs if isinstance(theirs, list) else list(theirs.values())
    tids = sorted(int(r["id"]) for r in trows if isinstance(r, dict) and str(r.get("id", "")).isdigit())
    say("  delta: %d rows, ids %s ... %s" % (len(tids), tids[:6], tids[-4:]))
    say("  delta ids NOT in ours: %s" % [i for i in tids if i not in gids])
    say("  our ids NOT in delta : %s" % [i for i in gids if i not in tids])

sys.stdout = io.open(os.path.join(ROOT, "logs", "delta_presence.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/delta_presence.txt")
