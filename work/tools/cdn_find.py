#!/usr/bin/env python3
"""What exactly did the earlier session archive from the live hotfix CDN, and does
it contain the content our APK lacks (notably the 2025-11 探秘东山岛 event)?"""
import io
import json
import os
import re
import sys

ROOT = r"H:\AI\frog"
CDN = os.path.join(ROOT, "work", "cdn")
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


say("=== work/cdn tree (top levels) ===")
for dp, dn, fn in os.walk(CDN):
    rel = os.path.relpath(dp, CDN)
    depth = 0 if rel == "." else rel.count(os.sep) + 1
    if depth <= 2:
        say("  %-46s %d files, %d dirs" % (rel, len(fn), len(dn)))
    if depth >= 3:
        dn[:] = []

say()
pj = os.path.join(CDN, "patch.json")
if os.path.isfile(pj):
    raw = open(pj, "rb").read()
    say("=== patch.json: %d bytes ===" % len(raw))
    try:
        j = json.loads(raw.decode("utf-8"))
        say("  top-level keys: %s" % list(j)[:10])
        for k in list(j)[:4]:
            v = j[k]
            say("  %s : %s" % (k, (str(v)[:300])))
    except Exception as e:
        say("  not JSON (%s); first 300 bytes: %r" % (e, raw[:300]))

say()
say("=== keywords across the archived CDN ===")
for kw in ["koto", "dongshan", "东山", "南门湾", "流星", "museum", "MuseumDay", "springcard"]:
    hits = []
    for dp, dn, fn in os.walk(CDN):
        for f in fn:
            p = os.path.join(dp, f)
            try:
                blob = open(p, "rb").read()
            except OSError:
                continue
            n = blob.count(kw.encode("utf-8"))
            if n:
                hits.append("%s x%d" % (os.path.relpath(p, CDN), n))
    say("  %-12s %2d files  %s" % (kw, len(hits), ", ".join(hits[:4])))

say()
mf = os.path.join(CDN, "v1021", "manifest.json")
if os.path.isfile(mf):
    say("=== v1021/manifest.json ===")
    say("  " + open(mf, encoding="utf-8", errors="replace").read()[:400])

say()
say("=== does v1021 have a different ProtocolList (new commands)? ===")
old = os.path.join(ROOT, "work", "run", "web", "js", "main.min.js")
new = os.path.join(CDN, "v1021", "js", "main.min.js")
if os.path.isfile(new):
    so = io.open(old, encoding="utf-8", errors="replace").read()
    sn = io.open(new, encoding="utf-8", errors="replace").read()
    say("  our main.min.js : %d chars" % len(so))
    say("  v1021 main.min.js: %d chars" % len(sn))

    def protolist(src):
        m = re.search(r"var ProtocolList=function\(\)\{function e\(\)\{return\{", src)
        if not m:
            return set()
        seg = src[m.end():m.end() + 60000]
        return set(re.findall(r"([a-z][a-z0-9_]{3,})\s*:\s*\[\[", seg))

    po, pn = protolist(so), protolist(sn)
    say("  commands only in v1021: %s" % (", ".join(sorted(pn - po)) or "NONE"))
    say("  commands only in ours : %s" % (", ".join(sorted(po - pn)) or "NONE"))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "cdn_find.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/cdn_find.txt")
