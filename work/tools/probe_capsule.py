"""The capsule (扭蛋) subsystem: protocol, model, and table."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol entries')
print('=' * 78)
m = re.search(r'capsule_load:', src)
print(src[m.start():m.start() + 420].replace('\n', ' ') if m else 'NOT FOUND')
print()

for pat, win, limit in [(r'CapsuleModel', 1600, 1),
                        (r'capsule_twist', 500, 2),
                        (r'capsule_patch', 500, 2),
                        (r'capsule_get_coin', 450, 2),
                        (r'capsule_fast_task', 450, 2)]:
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
        if n >= limit:
            break
    if n == 0:
        print('  (no match)')
    print()

T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')
d = json.load(open(os.path.join(T, 'capsuleData.json'), encoding='utf-8'))
print('--- capsuleData.json (%s, %d) ---' % (type(d).__name__, len(d)))
print(json.dumps(d, ensure_ascii=False)[:1000])
