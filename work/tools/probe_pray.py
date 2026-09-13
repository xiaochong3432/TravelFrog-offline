"""pray_* and wishingpool_*: protocol signatures, the models, and the tables."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol entries')
print('=' * 78)
for key in ['pray_load_grays:', 'pray_compose:', 'pray_confirm_make_box:',
            'wishingpool_load:', 'wishingpool_wish:']:
    m = re.search(re.escape(key), src)
    print('%-26s %s' % (key, src[m.start():m.start() + 120].replace('\n', ' ')
                        if m else 'NOT FOUND'))
print()

for pat, win in [(r'PrayModel', 1500), (r'WishingPoolModel', 1200),
                 (r'pray_compose', 500), (r'pray_confirm_make_box', 500),
                 (r'wishingpool_wish', 500)]:
    print('=' * 78)
    print('### %s' % pat)
    print('=' * 78)
    seen = set()
    n = 0
    for mm in re.finditer(pat, src):
        seg = src[max(0, mm.start() - win):mm.start() + win].replace('\n', ' ')
        if seg[:50] in seen:
            continue
        seen.add(seg[:50])
        print(seg)
        print('-' * 40)
        n += 1
        if n >= 1:
            break
    if n == 0:
        print('  (no match)')
    print()

T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')
for f in ['prayData', 'prayBodyData', 'prayNoteData', 'GoalNumber']:
    p = os.path.join(T, f + '.json')
    if not os.path.exists(p):
        print('--- %s MISSING' % f)
        continue
    d = json.load(open(p, encoding='utf-8'))
    print('--- %s (%s, %d) ---' % (f, type(d).__name__, len(d)))
    print('   ', json.dumps(d, ensure_ascii=False)[:420])
