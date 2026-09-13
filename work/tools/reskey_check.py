#!/usr/bin/env python3
"""Which resource file defines a given resource key, and does its PNG exist?

The annual-review skins ask for `year_summary_png` / `year_summary_review_png` /
`year_summary_share_png`; if those keys are declared in default.res.json but the
file is missing from the tree, the view renders partially blank -- worth knowing
before deciding whether the feature is salvageable.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
import os
import sys

WEB = str(PROJECT_ROOT) + "/work/run/web"
needles = sys.argv[1:] or ["year_summary", "summary_page", "theme_paper"]

res = os.path.join(WEB, "resource", "China", "default.res.json")
with open(res, encoding="utf-8") as fh:
    cfg = json.load(fh)

keys = set()
for g in cfg.get("groups", []):
    for k in (g.get("keys") or "").split(","):
        if k:
            keys.add(k)
for r in cfg.get("resources", []):
    for k in (r.get("keys") or "").split(","):
        if k:
            keys.add(k)
print("resource keys in default.res.json: %d" % len(keys))

for n in needles:
    hits = sorted(k for k in keys if n in k)
    print("\n=== keys containing %r (%d) ===" % (n, len(hits)))
    for k in hits:
        # Egret resource keys end in "_png"/"_jpg"/"_json" rather than ".png".
        # Getting this wrong makes EVERY key look missing, so try the raw name
        # first and then the extension-rewritten form.
        cands = [k]
        m = k.rsplit("_", 1)
        if len(m) == 2 and m[1] in ("png", "jpg", "jpeg", "json", "xml", "fnt", "atlas", "mp3", "mp4"):
            cands.append(m[0] + "." + m[1])
        found = []
        for dp, dn, fn in os.walk(os.path.join(WEB, "resource", "China")):
            for f in fn:
                if f in cands:
                    found.append(os.path.join(dp, f))
        print("  %-34s %s" % (k, ("OK " + found[0].replace(WEB, "")) if found else "*** FILE NOT FOUND (tried %s) ***" % cands))
