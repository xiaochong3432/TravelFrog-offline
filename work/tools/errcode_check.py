#!/usr/bin/env python3
"""Does the client have the errcode table that every `{code:N}` reply depends on?

`MessageModel.getErrorInfo(code)` reads `RES.getRes("errcode_json")`. Call sites
treat a MISSING entry as "no error object", so a reply of `{code:0}` whose table
is absent makes the caller skip its success branch entirely -- a dead button even
though the server answered. This script answers: is errcode.json in our tree, in
the engine's extracted tables, and in default.res.json?
"""
import io
import json
import os
import re
import sys

ROOT = r"H:\AI\frog\work"
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


hits = []
for dp, dn, fn in os.walk(os.path.join(ROOT, "run", "web")):
    for x in fn:
        if "errcode" in x.lower():
            hits.append(os.path.relpath(os.path.join(dp, x), ROOT))
say("files named *errcode* under run/web: %s" % (hits or "NONE"))

GD = json.load(open(os.path.join(ROOT, "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
tabs = GD.get("tables", {})
say("gamedata tables containing 'rror'/'rrcode': %s"
    % [k for k in tabs if "rror" in k or "rrcode" in k])

res = os.path.join(ROOT, "run", "web", "resource", "China", "default.res.json")
txt = io.open(res, encoding="utf-8", errors="replace").read()
say("default.res.json mentions errcode: %s" % ("errcode" in txt))
for m in re.finditer("errcode", txt):
    say("   ...%s..." % txt[max(0, m.start() - 160):m.end() + 160].replace("\n", " "))

# Where do the client's *_json resources actually come from in our shell?
for name in ("__probe.js", "__offline-engine.js"):
    p = os.path.join(ROOT, "run", "web", name)
    if os.path.exists(p):
        t = io.open(p, encoding="utf-8", errors="replace").read()
        say("%s mentions errcode: %d" % (name, t.count("errcode")))
        for m in re.finditer(r"getRes|RES\.", t):
            pass

# The engine's own reply codes: what does it use?
eng = io.open(os.path.join(ROOT, "run", "engine", "index.js"), encoding="utf-8").read()
codes = {}
for m in re.finditer(r"code:\s*(-?\d+)", eng):
    codes[m.group(1)] = codes.get(m.group(1), 0) + 1
say("engine reply codes used: %s" % sorted(codes.items(), key=lambda kv: -kv[1]))

sys.stdout = open(os.path.join(ROOT, "logs", "errcode_check.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/errcode_check.txt")
