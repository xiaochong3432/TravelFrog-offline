"""Is travel_load_gift the ALBUM or a separate GIFT BOX holding area?

This decides whether drop-on-trip-return rewards should go straight into the
album (what the engine does today) or into the gift box first.
"""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

for pat, win, limit in [
    (r'GiftBoxModel=function', 1400, 1),
    (r'GiftBoxModel', 260, 4),
    (r'getPictureInfoList|pictureInfoList', 300, 3),
    (r'GiftBoxController', 300, 2),
    (r'specialityList\.source', 300, 2),
]:
    print('=' * 78)
    print('### %s' % pat)
    print('=' * 78)
    n = 0
    seen = set()
    for m in re.finditer(pat, src):
        seg = src[max(0, m.start() - win):m.start() + win].replace('\n', ' ')
        if seg[:50] in seen:
            continue
        seen.add(seg[:50])
        print(seg)
        print('-' * 40)
        n += 1
        if n >= limit:
            break
    if n == 0:
        print('  (no match)')
    print()
