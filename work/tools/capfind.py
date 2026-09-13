#!/usr/bin/env python3
"""Find the capsule (扭蛋机) view/controller class names and who opens them, plus
the garden button handler."""
import re

JS = r"H:\AI\frog\work\run\web\js\main.min.js"
with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()

for pat in [r"Capsule/CapsuleSkin\.exml", r"on_capsuleBtn_tap", r"btnCapsule"]:
    hits = list(re.finditer(pat, s))
    print("=" * 16, pat, "(%d)" % len(hits))
    for m in hits[:3]:
        a, b = max(0, m.start() - 700), min(len(s), m.end() + 500)
        print("  @%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
        print()
