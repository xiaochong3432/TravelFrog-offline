"""The DrawingModel / guest_* subsystem: protocol signatures, the state enum,
and what pages/colls mean."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol table: guest_* and drawing_*')
print('=' * 78)
m = re.search(r'guest_load:\[', src)
if m:
    print(src[m.start():m.start() + 430].replace('\n', ' '))
print()

for pat, win in [(r'DrawingState', 380), (r'DrawingEventType', 320)]:
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
        if n >= 2:
            break
    print()

print('=' * 78)
print('### DrawingModel full body (first 2600 chars)')
print('=' * 78)
i = src.find('var DrawingModel=function')
print(src[i:i + 2600].replace('\n', ' '))

print()
T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')
for f in ['drawingPageData', 'drawingCollectData', 'drawingCommonData']:
    d = json.load(open(os.path.join(T, f + '.json'), encoding='utf-8'))
    print('--- %s (%s, %d) ---' % (f, type(d).__name__, len(d)))
    print('   ', json.dumps(d, ensure_ascii=False)[:520])
