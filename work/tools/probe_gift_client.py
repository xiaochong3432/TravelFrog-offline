"""Find gift-box / album capacities and the remaining gift-related commands."""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

PATS = [
    (r'travel_read_note', 520, 2),
    (r'item_select_gift', 520, 2),
    (r'getErrorInfo', 420, 2),
    (r'101\s*:|102\s*:', 260, 3),
    (r'GiftBoxMax|gift_max|GiftMax|AlbumMax|album_max|PHOTO_MAX|photo_max', 320, 4),
    (r'specialtys', 300, 3),
]

for pat, win, limit in PATS:
    print('=' * 78)
    print('### %s' % pat)
    print('=' * 78)
    n = 0
    seen = set()
    for m in re.finditer(pat, src):
        seg = src[max(0, m.start() - win):m.start() + win].replace('\n', ' ')
        key = seg[:60]
        if key in seen:
            continue
        seen.add(key)
        print(seg)
        print('-' * 40)
        n += 1
        if n >= limit:
            break
    if n == 0:
        print('  (no match)')
    print()
