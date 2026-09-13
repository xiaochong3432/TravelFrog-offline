#!/usr/bin/env python3
"""Dump the shapes needed to build valid springcard / greetcard / partycake payloads."""
import io
import json
import os
import sys

ROOT = r"H:\AI\frog\work"
GD = json.load(open(os.path.join(ROOT, "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


for name in ["springCard", "greetCard", "PartyCakeData"]:
    v = T.get(name)
    say("=" * 70)
    say("=== %s  type=%s" % (name, type(v).__name__))
    if isinstance(v, dict):
        for k, row in v.items():
            if isinstance(row, dict):
                ks = list(row.keys())[:10]
                say("  [%s] dict keys=%d %s" % (k, len(row), ks))
                for kk in list(row.keys())[:3]:
                    say("       %s -> %s" % (kk, json.dumps(row[kk], ensure_ascii=False)[:220]))
            elif isinstance(row, list):
                say("  [%s] list n=%d  first=%s" % (k, len(row),
                    json.dumps(row[0], ensure_ascii=False)[:260] if row else "-"))
            else:
                say("  [%s] = %s" % (k, json.dumps(row, ensure_ascii=False)[:200]))
    say()

# item ids that must be renderable
say("=== a few Item rows used in payloads ===")
for iid in [14, 47, 53, 101, 102, 107, 110, 200006, 200008, 200009, 200010, 200012, 200013]:
    it = next((i for i in GD["items"] if i["id"] == iid), None)
    say("  %-7s %s" % (iid, (it.get("name") + " type=" + str(it.get("type"))) if it else "ABSENT"))

sys.stdout = io.open(os.path.join(ROOT, "logs", "card_tables.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/card_tables.txt")
