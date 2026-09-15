"""Read what the client does with the ad / free-shop / recharge commands, so the
"click it and just get it" behaviour can be wired to the right fields."""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TU = os.path.abspath(os.path.join(HERE, '..'))
src = open(os.path.join(TU, 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

for kw in ['adsmgr_shop_free', 'adsmgr_share"', 'adsmgr_load',
           'recharge_load', 'recharge_ready_pay', 'recharge_water']:
    print('=' * 76)
    print('### %s' % kw)
    print('=' * 76)
    hits = [m.start() for m in re.finditer(re.escape(kw), src)]
    seen = set()
    n = 0
    for h in hits:
        seg = src[max(0, h - 700):h + 500].replace('\n', ' ')
        if seg[:50] in seen:
            continue
        seen.add(seg[:50])
        print(seg)
        print('-' * 30)
        n += 1
        if n >= 2:
            break
    if not hits:
        print('  (none)')
    print()
