"""The cooking (料理) subsystem: protocol, model, tables."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol entries')
print('=' * 78)
m = re.search(r'cooking_load_cooking:', src)
print(src[m.start():m.start() + 320].replace('\n', ' ') if m else 'NOT FOUND')
print()

print('=' * 78)
print('### CookingModel')
print('=' * 78)
i = src.find('var CookingModel=function')
print(src[i:i + 2600].replace('\n', ' ') if i > 0 else 'NOT FOUND')
print()

T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')
for f in ['cookingData', 'cookingTaskData']:
    d = json.load(open(os.path.join(T, f + '.json'), encoding='utf-8'))
    print('--- %s (%s, %d) ---' % (f, type(d).__name__, len(d)))
    if isinstance(d, dict):
        for k in list(d.keys())[:4]:
            print('  %-8s %s' % (k, json.dumps(d[k], ensure_ascii=False)[:300]))
    else:
        print('  ', json.dumps(d, ensure_ascii=False)[:600])
