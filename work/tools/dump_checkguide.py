#!/usr/bin/env python3
"""Dump MainOutView.checkGuide (tutorial gating) for offline handling."""
import re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

i = d.find("t.prototype.checkGuide=function")
if i < 0:
    i = d.find("checkGuide=function")
seg = d[i:i + 6000]
seg = re.sub(r'([;{}])', r'\1\n', seg)
open(r"H:\AI\frog\work\checkguide.txt", "w", encoding="utf8").write(seg)
print(seg[:5200])
