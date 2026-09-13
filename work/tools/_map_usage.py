"""Which define.json MAPS does the engine actually consume?"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
d = json.load(open(os.path.join(ROOT, 'run', 'engine', 'data', 'define.json'),
                   encoding='utf-8'))
maps = d.get('maps', {})
eng = open(os.path.join(ROOT, 'run', 'engine', 'index.js'), encoding='utf-8').read()

print('define.json maps: %d' % len(maps))
used = 0
unused = []
for k in sorted(maps):
    hit = ("'%s'" % k) in eng
    if hit:
        used += 1
    else:
        unused.append(k)
    print('  %-28s used=%-5s %s' % (k, hit, json.dumps(maps[k], ensure_ascii=False)[:80]))
print()
print('used %d / %d' % (used, len(maps)))
print('UNUSED maps: %s' % ', '.join(unused))
