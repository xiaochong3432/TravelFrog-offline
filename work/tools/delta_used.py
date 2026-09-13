#!/usr/bin/env python3
"""Does OUR client actually reference the 1.0.21 assets?

Two questions decide whether merging the 1.0.21 art buys anything:
  1. Are the "missing" PNGs simply packed inside an .eab (my loose-file scan missed them)?
  2. Does this build's main.min.js / default.res.json mention the new 1.0.21 pieces
     (back_mainout_2_*, courtyard spine, icon2/icon3 sheets, furniture_xw3 sheet)?
     Art a client never loads is not a merge, it is dead weight.
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

ROOT = str(PROJECT_ROOT) + "/work"
EAB = os.path.join(ROOT, "run", "web", "resource", "China", "eab")
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()
RES = io.open(os.path.join(ROOT, "run", "web", "resource", "China", "default.res.json"),
              encoding="utf-8", errors="replace").read()
THM = io.open(os.path.join(ROOT, "run", "web", "js", "default.thm.js"),
              encoding="utf-8", errors="replace").read()
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


def eab_names():
    names = {}
    for f in sorted(os.listdir(EAB)):
        if not f.endswith(".eab"):
            continue
        p = os.path.join(EAB, f)
        data = open(p, "rb").read()
        if data[6:7] != b"\x1a":
            continue
        idx_len = int.from_bytes(data[8:12], "little")
        try:
            idx = json.loads(data[12:12 + idx_len].decode("utf-8"))
        except Exception:
            continue
        for e in idx:
            n = e.get("n")
            if n:
                names[n] = f
    return names


EABN = eab_names()
say("=== %d names inside the plaintext .eab bundles ===" % len(EABN))

CHECK = ["back_mainout_2_top", "back_mainout_2_base", "back_mainout_2_mid",
         "courtyard", "icon2_sheet", "icon3_sheet", "furniture_xw3", "furniture_xw1",
         "furniture_xw0", "time_bg", "title_bg", "u_month4", "shop_title_xt"]
say()
say("=== are the 'missing' files actually inside an .eab? ===")
for c in CHECK:
    hits = [k for k in EABN if c.lower() in k.lower()]
    say("  %-22s %s" % (c, ("IN " + EABN[hits[0]] + " -> " + ", ".join(hits[:3])) if hits else "NOT IN ANY .eab"))

say()
say("=== does OUR client reference them? (main.min.js / default.thm.js / default.res.json) ===")
for c in CHECK + ["g_bwg_shanxi", "bwg_sx1", "xw3_1", "BWG_WWH2", "bwg_wwh2"]:
    say("  %-22s js=%-4d thm=%-4d res=%-4d"
        % (c, CLIENT.count(c), THM.count(c), RES.count(c)))

say()
say("=== the 1.0.21 client's own default.res.json: what did IT add? ===")
DELTA = os.path.join(ROOT, "cdn", "live")
dres = None
for band in os.listdir(DELTA):
    for dp, dn, fn in os.walk(os.path.join(DELTA, band)):
        if "default.res.json" in fn:
            dres = os.path.join(dp, "default.res.json")
if dres:
    theirs = json.load(open(dres, encoding="utf-8"))
    ours = json.loads(RES)
    def key(d):
        return {r.get("name"): r for r in d.get("resources", []) if r.get("name")}
    ko, kt = key(ours), key(theirs)
    added = [k for k in kt if k not in ko]
    removed = [k for k in ko if k not in kt]
    changed = [k for k in kt if k in ko and json.dumps(ko[k], sort_keys=True) != json.dumps(kt[k], sort_keys=True)]
    say("  delta adds %d resources, removes %d, changes %d"
        % (len(added), len(removed), len(changed)))
    say("  added sample   : %s" % added[:14])
    say("  changed sample : %s" % changed[:14])
    say("  our groups: %s" % [g.get("name") for g in ours.get("groups", [])][:12])
    say("  delta groups: %s" % [g.get("name") for g in theirs.get("groups", [])][:12])

sys.stdout = io.open(os.path.join(ROOT, "logs", "delta_used.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/delta_used.txt")
