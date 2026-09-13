#!/usr/bin/env python3
"""Find code that could restart the tutorial (guideStep / GuideStep.New)."""
import re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

pats = [
    ('setClientSettings("guideStep"', r'setClientSettings\(\s*"guideStep"'),
    ('getNextGuideStep(GuideStep.New)', r'getNextGuideStep\(\s*GuideStep\.New\s*\)'),
    ('GuideStep.New bare use', r'GuideStep\.New'),
]
for label, p in pats:
    print(f"\n===== {label} =====")
    hits = [m.start() for m in re.finditer(p, d)]
    print(f"  {len(hits)} occurrence(s)")
    for h in hits[:10]:
        seg = d[max(0, h - 300):h + 200].replace("\n", " ")
        print(f"  [{h}] ...{seg}...")
