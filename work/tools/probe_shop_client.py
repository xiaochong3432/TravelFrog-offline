"""Find how the client builds the furniture shop UI: shop_list shape, fields read."""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

PATS = [
    (r'shop_list', 420, 4),
    (r'FurnitureShopDB', 300, 3),
    (r'getShopList|shopList', 360, 3),
    (r'has_item', 300, 3),
    (r'FurnitureShopController', 340, 3),
]

for pat, win, limit in PATS:
    print('=' * 78)
    print('### %s' % pat)
    print('=' * 78)
    n = 0
    seen = set()
    for m in re.finditer(pat, src):
        seg = src[max(0, m.start() - win):m.start() + win].replace('\n', ' ')
        if seg[:60] in seen:
            continue
        seen.add(seg[:60])
        print(seg)
        print('-' * 40)
        n += 1
        if n >= limit:
            break
    if n == 0:
        print('  (no match)')
    print()
