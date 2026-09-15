"""Finish the animpicture (动态照片) contract: the 4 commands I have not read,
plus the phase gate and the data table."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

i = src.find('var AnimPictureModel')
seg = src[i:i + 6000]
print('=' * 78)
print('### AnimPictureModel, the part after req_remove_pic')
print('=' * 78)
j = seg.find('req_remove_pic')
print(seg[j:j + 3400].replace('\n', ' '))
print()

print('=' * 78)
print('### where `phase` is READ (the flow gate)')
print('=' * 78)
seen = set()
n = 0
for m in re.finditer(r'\.phase\b', src):
    s = src[max(0, m.start() - 220):m.start() + 220].replace('\n', ' ')
    if s[:45] in seen:
        continue
    seen.add(s[:45])
    print(s)
    print('-' * 30)
    n += 1
    if n >= 5:
        break
print()

T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')
d = json.load(open(os.path.join(T, 'animpictureData.json'), encoding='utf-8'))
print('--- animpictureData.json keys: %s' % list(d.keys()))
print('  base_info:', json.dumps(d.get('base_info'), ensure_ascii=False))
lst = d.get('list') or {}
print('  list rows: %d' % len(lst))
for k in list(lst.keys())[:2]:
    print('   %s -> %s' % (k, json.dumps(lst[k], ensure_ascii=False)[:420]))
pm = d.get('pic_map') or {}
print('  pic_map entries: %d  sample: %s' % (len(pm), json.dumps(dict(list(pm.items())[:6]))))
