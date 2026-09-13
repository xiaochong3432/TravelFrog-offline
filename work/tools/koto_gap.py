#!/usr/bin/env python3
"""Identify the `koto` protocol family (9 unimplemented commands) and check whether
the 2025-11 探秘东山岛 content exists anywhere in the package."""
import io
import json
import os
import re
import sys

ROOT = r"H:\AI\frog"
WEB = os.path.join(ROOT, "work", "run", "web")
JS = os.path.join(WEB, "js", "main.min.js")

out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


s = io.open(JS, encoding="utf-8", errors="replace").read()

say("=== client context around `koto` ===")
seen = 0
for m in re.finditer(r"[Kk]oto", s):
    a, b = max(0, m.start() - 260), min(len(s), m.end() + 200)
    ctx = s[a:b].replace("\n", " ")
    say("  @%d ...%s..." % (m.start(), ctx))
    seen += 1
    if seen >= 6:
        break
say("  total mentions: %d" % len(re.findall(r"[Kk]oto", s)))

say()
say("=== 探秘东山岛 keywords anywhere in the client bundle ===")
for kw in ["东山", "南门湾", "流星", "野营", "探秘", "护身符", "福建", "漳州", "koto"]:
    hits = len(re.findall(re.escape(kw), s))
    say("  %-8s %d" % (kw, hits))

say()
say("=== and in the resource tree (any file type) ===")
for kw in ["东山", "南门湾", "流星", "野营", "koto", "Koto"]:
    found = []
    for dp, dn, fn in os.walk(os.path.join(WEB, "resource")):
        for f in fn:
            if kw.lower() in f.lower():
                found.append(os.path.relpath(os.path.join(dp, f), WEB))
    say("  %-8s %d  %s" % (kw, len(found), ", ".join(found[:3])))

say()
say("=== same keywords inside the .eab bundles (names live in the index) ===")
for kw in ["东山", "南门湾", "流星", "koto", "museum", "博物馆"]:
    total = 0
    where = []
    for dp, dn, fn in os.walk(os.path.join(WEB, "resource", "China", "eab")):
        for f in fn:
            p = os.path.join(dp, f)
            blob = open(p, "rb").read()
            n = blob.count(kw.encode("utf-8"))
            if n:
                total += n
                where.append("%s x%d" % (f, n))
    say("  %-8s %d  %s" % (kw, total, ", ".join(where[:4])))

say()
say("=== the client's own data tables for these events ===")
GD = json.load(open(os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD.get("tables", {})
for k in sorted(T):
    if re.search(r"koto|museum|party|spring|greet", k, re.I):
        t = T[k]
        rows = t if isinstance(t, list) else list(t.values()) if isinstance(t, dict) else []
        sample = []
        for r in rows[:3]:
            if isinstance(r, dict):
                for kk in ("name", "title", "desc", "info", "city", "province"):
                    if isinstance(r.get(kk), str) and r[kk]:
                        sample.append(r[kk])
                        break
        say("  %-22s %d rows  %s" % (k, len(rows), " | ".join(sample[:3])))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "koto_gap.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/koto_gap.txt")
