"""Targeted searches in main.min.js for the furniture subsystem."""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

PATTERNS = [
    (r'furniture_replace_\w+', 420),
    (r'pocketData\.clover\s*=', 320),
    (r'pocketData\.clover\s*\+=', 320),
    (r'furniture_buy_shop', 620),
    (r'replace_fur', 380),
    (r'serverData\.bench\s*=', 260),
    (r'pocketCommonData', 300),
]

for pat, win in PATTERNS:
    print('=' * 78)
    print('### %s' % pat)
    print('=' * 78)
    seen = set()
    n = 0
    for m in re.finditer(pat, src):
        seg = src[max(0, m.start() - win):m.start() + win]
        key = seg[:80]
        if key in seen:
            continue
        seen.add(key)
        print(seg.replace('\n', ' '))
        print('-' * 40)
        n += 1
        if n >= 3:
            break
    if n == 0:
        print('  (no match)')
    print()
