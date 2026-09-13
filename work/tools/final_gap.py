#!/usr/bin/env python3
"""Last checks for the comparison:

  * are the 1.0.18 behaviours 照镜子 / 吃西瓜 anywhere as ANIMATIONS (not items)?
  * what does our engine actually do for the museum (1.0.11 + the 2024-08 四馆联动)?
  * which season/summer art is present (1.0.16 winter, 1.0.18 summer + fireflies)?
"""
import io
import json
import os
import re
import sys

ROOT = r"H:\AI\frog"
WEB = os.path.join(ROOT, "work", "run", "web")
ENGINE = io.open(os.path.join(ROOT, "work", "run", "engine", "index.js"),
                 encoding="utf-8").read()
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


say("=== animation assets that could be 照镜子 / 吃西瓜 ===")
pats = ["mirror", "jingzi", "xigua", "watermelon", "chixigua", "egg_"]
found = {p: [] for p in pats}
for dp, dn, fn in os.walk(os.path.join(WEB, "resource")):
    for f in fn:
        for p in pats:
            if p in f.lower():
                found[p].append(os.path.relpath(os.path.join(dp, f), WEB))
for p in pats:
    say("  %-12s %d  %s" % (p, len(found[p]), ", ".join(found[p][:4])))

say()
say("=== every frog animation family present (dragonbones/spine folders) ===")
for dp, dn, fn in os.walk(os.path.join(WEB, "resource", "China")):
    base = os.path.basename(dp)
    if re.search(r"frog|motion|home|ie$", base, re.I):
        say("  %-46s %d files" % (os.path.relpath(dp, WEB), len(fn)))

say()
say("=== our engine's museum surface ===")
for m in re.finditer(r"^\s{4}(museum[a-z_]*|koto[a-z_]*)\s*:", ENGINE, re.M):
    say("  handler: " + m.group(1))
for kw in ["museumData", "museumDay", "Museum", "inspire", "compass"]:
    say("  %-12s engine hits: %d" % (kw, len(re.findall(kw, ENGINE))))

say()
say("=== the museum tables in the client's data ===")
GD = json.load(open(os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
for k in sorted(T):
    if "museum" in k.lower():
        t = T[k]
        rows = t if isinstance(t, list) else list(t.values())
        say("  %-20s %d rows" % (k, len(rows)))
        for r in rows[:4]:
            if isinstance(r, dict):
                say("      %s" % json.dumps(r, ensure_ascii=False)[:150])

say()
say("=== season art: winter / summer / fireflies ===")
for kw in ["season11", "season12", "season13", "season14", "season21", "season22",
           "season23", "season24", "season31", "season32", "season33", "season34",
           "season41", "season42", "season43", "season44", "firefly", "snow", "xue"]:
    n = sum(1 for dp, dn, fn in os.walk(os.path.join(WEB, "resource", "China"))
            for f in fn if kw in f.lower())
    say("  %-10s %d files" % (kw, n))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "final_gap.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/final_gap.txt")
