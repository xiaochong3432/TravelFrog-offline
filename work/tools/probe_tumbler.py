"""The tumbler (不倒翁) display: protocol, model, and the exact `layers` shape."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
TU = os.path.abspath(os.path.join(HERE, '..'))
src = open(os.path.join(TU, 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### TumblerLoader (what `layers` must look like)')
print('=' * 78)
for kw in ['TumblerLoader', 'load_tumbler', 'tumbler_list']:
    hits = [m.start() for m in re.finditer(re.escape(kw), src)]
    print('--- %s : %d hits' % (kw, len(hits)))
    for h in hits[:2]:
        print(src[max(0, h - 500):h + 700].replace('\n', ' '))
        print('   ...')
    print()

print('=' * 78)
print('### engines current tumbler handlers')
print('=' * 78)
eng = open(os.path.join(TU, 'run', 'engine', 'index.js'), encoding='utf-8').read()
for m in re.finditer(r'^\s{4}(furniture_load_tumbler|furniture_replace_tumbler)\s*:.*', eng, re.M):
    print('  ' + m.group(0).strip())

T = os.path.join(TU, 'run', 'engine', 'data', 'tables')
td = json.load(open(os.path.join(T, 'tumblerData.json'), encoding='utf-8'))
tp = json.load(open(os.path.join(T, 'tumblerPathData.json'), encoding='utf-8'))
print()
print('tumblerData rows: %d, first: %s' % (len(td), json.dumps(td[0], ensure_ascii=False)))
print('tumblerPathData rows: %d' % len(tp))
for r in tp[:6]:
    print('   ', json.dumps(r, ensure_ascii=False))
