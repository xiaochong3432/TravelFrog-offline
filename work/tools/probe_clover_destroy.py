"""How is CloverDestroyTime used? (a rule we never implemented)"""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TU = os.path.abspath(os.path.join(HERE, '..'))
src = open(os.path.join(TU, 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

for kw in ['CloverDestroyTime', 'rebirth_span', 'last_harvest', 'destroy']:
    hits = [m.start() for m in re.finditer(re.escape(kw), src)]
    print('=' * 74)
    print('### %s : %d hits' % (kw, len(hits)))
    print('=' * 74)
    seen = set()
    n = 0
    for h in hits:
        seg = src[max(0, h - 380):h + 380].replace('\n', ' ')
        if seg[:50] in seen:
            continue
        seen.add(seg[:50])
        print(seg)
        print('-' * 28)
        n += 1
        if n >= 3:
            break
    if not hits:
        print('  (none)')
    print()

eng = open(os.path.join(TU, 'run', 'engine', 'index.js'), encoding='utf-8').read()
print('=' * 74)
print('### our engine: clover fields it stores / withering')
print('=' * 74)
for m in re.finditer(r'^\s*out\.push\(\{[^}]*clover_id[^}]*\}\)', eng, re.M | re.S):
    print(m.group(0))
for kw in ['rebirth_span', 'CloverDestroyTime', 'wither', 'destroyTime']:
    print('  engine mentions %-18s %s' % (kw, kw in eng))
