"""The museumday (博物馆日) subsystem: protocol, model, tables."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol entries')
print('=' * 78)
m = re.search(r'museumday_load:', src)
print(src[m.start():m.start() + 460].replace('\n', ' ') if m else 'NOT FOUND')
print()

i = src.find('var MuseumDayModel')
print('=' * 78)
print('### MuseumDayModel')
print('=' * 78)
print(src[i:i + 3000].replace('\n', ' ') if i > 0 else 'NOT FOUND')
print()

T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')
for f in ['museumData', 'museumDayData', 'museumDayDesc', 'museumDayCommon']:
    p = os.path.join(T, f + '.json')
    if not os.path.exists(p):
        print('--- %s MISSING' % f)
        continue
    d = json.load(open(p, encoding='utf-8'))
    print('--- %s (%s, %d) ---' % (f, type(d).__name__, len(d)))
    print('   ', json.dumps(d, ensure_ascii=False)[:520])
    print()
