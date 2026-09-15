"""Where do trip-return rewards land -- the gift box or straight in the album?

Looks at how the client handles the trip-return event's evt_pic / evt_value, and
at what the gift box UI is bound to.
"""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

for pat, win, limit in [
    (r'evt_pic', 380, 4),
    (r'revice_mails|revice_events', 300, 2),
    (r'getGiftBox|GiftBox\.', 300, 3),
    (r'specialtys\b', 300, 3),
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
