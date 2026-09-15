"""Dump the furniture tuning table and the interesting furniture rows.

furnitureCommon.json is {id: {id, value}} -- a tuning-constant table like
Tabikaeru.Define, so it is where rates/thresholds for this subsystem would live.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')
load = lambda n: json.load(open(os.path.join(T, n + '.json'), encoding='utf-8'))

fc = load('furnitureCommon')
print('=== furnitureCommon.json (%d rows: id -> value) ===' % len(fc))
for k in sorted(fc, key=lambda x: int(x)):
    print('  %-8s %s' % (k, json.dumps(fc[k].get('value'), ensure_ascii=False)))

fd = load('furnitureData')
print()
print('=== furnitureData.json keys and 3 full rows ===')
k0 = list(fd.keys())[0]
print('  fields: %s' % list(fd[k0].keys()))
for k in list(fd.keys())[:3]:
    print('  %s' % json.dumps(fd[k], ensure_ascii=False)[:400])

fs = load('furnitureShopData')
print()
print('=== furnitureShopData.json 3 full rows ===')
for k in list(fs.keys())[:3]:
    print('  %s' % json.dumps(fs[k], ensure_ascii=False)[:400])
print('  price range: %s' % sorted(set(r.get('price') for r in fs.values()))[:14])

bd = load('benchData')
print()
print('=== benchData.json types ===')
import collections
print('  type counts: %s' % collections.Counter(r['type'] for r in bd))
print('  type 1 ids : %s' % [r['id'] for r in bd if r['type'] == 1][:20])

it = load('Item')
byid = {r['id']: r for r in it} if isinstance(it, list) else {}
print()
print('=== do shop item_ids exist in Item.json? ===')
missing = []
for r in list(fs.values())[:40]:
    if r.get('item_id') not in byid:
        missing.append(r.get('item_id'))
print('  missing from Item.json (first 40 shop rows): %s' % missing[:10])
sample = [r['item_id'] for r in list(fs.values())[:3]]
for s in sample:
    print('  item %s -> %s' % (s, json.dumps(byid.get(s), ensure_ascii=False)[:220]))
