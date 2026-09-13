#!/usr/bin/env python3
"""Find code that could restart the tutorial (guideStep / GuideStep.New)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
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
