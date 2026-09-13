#!/usr/bin/env python3
"""Both handbook payload contracts: what the engine sends, what the client expects.

Reports:
  * the engine's item_load_handbook / encyclopedia_load replies and every place
    `state.handbook` is written (if nothing writes it, every entry stays "?")
  * the client's handlers for those two commands
  * what the client's renderers do with the data (which field means "collected")
"""
import io
import os
import re

ROOT = r"H:\AI\frog\work"
ENGINE = io.open(os.path.join(ROOT, "run", "engine", "index.js"), encoding="utf-8").read()
CLIENT = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
                 encoding="utf-8", errors="replace").read()
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


say("=== engine: item_load_handbook / encyclopedia_load ===")
for pat in [r"    item_load_handbook: ", r"    encyclopedia_load: "]:
    for m in re.finditer(pat, ENGINE):
        say("L%d: %s" % (ENGINE.count("\n", 0, m.start()) + 1,
                         ENGINE[m.start():m.start() + 700].split("\n\n")[0][:650]))
say()

say("=== engine: every write to state.handbook ===")
for m in re.finditer(r"handbook[.\[]", ENGINE):
    ln = ENGINE.count("\n", 0, m.start()) + 1
    a = ENGINE.rfind("\n", 0, m.start()) + 1
    b = ENGINE.find("\n", m.end())
    line = ENGINE[a:b].strip()
    if "push" in line or "=" in line or "indexOf" in line:
        say("  L%-5d %s" % (ln, line[:150]))
say()

say("=== client: item_load_handbook ===")
i = CLIENT.find("item_load_handbook=function")
say(CLIENT[i:i + 900] if i > 0 else "NOT FOUND")
say()
say("=== client: encyclopedia_load (EncyModel) ===")
i = CLIENT.find("encyclopedia_load=function")
say(CLIENT[i:i + 900] if i > 0 else "NOT FOUND")
say()
say("=== client: what marks a handbook entry as collected? ===")
for kw in ["getCollectionsList", "getSpecialtyList", "CollectDB", "SpecialtyDB"]:
    hits = [m.start() for m in re.finditer(re.escape(kw), CLIENT)]
    say("--- %s : %d" % (kw, len(hits)))
    for h in hits[:2]:
        say("   ...%s..." % CLIENT[max(0, h - 260):h + 320].replace("\n", " "))
    say()

io.open(os.path.join(ROOT, "logs", "handbook_gap.txt"), "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/handbook_gap.txt")
