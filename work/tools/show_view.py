#!/usr/bin/env python3
"""Print the [view] / [view-keys] / [res] probe reports from the client log."""
import re, sys

P = r"H:\AI\frog\work\run\logs\client.log"
txt = open(P, encoding="utf8", errors="replace").read()
for tag in ("[view]", "[view-keys]", "[res]", "[tree]", "[view-error]", "[tree-error]"):
    i = txt.find(tag)
    if i < 0:
        print(f"--- {tag}: absent")
        continue
    print(f"\n===== {tag} =====")
    print(txt[i:i + 4200])
