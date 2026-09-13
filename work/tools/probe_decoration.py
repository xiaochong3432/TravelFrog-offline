"""The 庭院装饰 (decoration) subsystem."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol entries')
print('=' * 78)
for key in ['client_load_decorate:', 'client_change_decorate:',
            'client_set_pic_show:']:
    m = re.search(re.escape(key), src)
    print('%-26s %s' % (key, src[m.start():m.start() + 120].replace('\n', ' ')
                        if m else 'NOT FOUND'))
print()

for pat, win, limit in [(r'Decorat', 1200, 2), (r'client_change_decorate', 520, 3),
                        (r'DecorationModel', 1000, 1)]:
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
d = json.load(open(os.path.join(T, 'decoration.json'), encoding='utf-8'))
print('--- decoration.json (%d rows) ---' % len(d))
for k in sorted(d, key=lambda x: int(x))[:8]:
    print('  %-6s %s' % (k, json.dumps(d[k], ensure_ascii=False)[:230]))
