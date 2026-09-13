#!/usr/bin/env python3
"""Find the achievement UI paths: the list view, the "new title" popup, and who
reads useAchieveID / cur_achieve."""
import re

JS = r"H:\AI\frog\work\run\web\js\main.min.js"
with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()

for pat in [r"getUseAchieveID", r"isAchieveExpire", r"AchieveViewController",
            r"getAchieveInfoList", r"AchieveDB", r"updateAchieveID"]:
    hits = list(re.finditer(pat, s))
    print("=" * 18, pat, "(%d)" % len(hits))
    for m in hits[:4]:
        a, b = max(0, m.start() - 380), min(len(s), m.end() + 260)
        print("  @%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
        print()
