# -*- coding: utf-8 -*-
"""Second pass: pin down the joins the walker needs.

Questions:
  1. Is NodeEdge keyed 1:1 by node id (arrival semantics) or many-per-node?
  2. What does Picture.place / Picture.type / PictureTag.tagType look like, and how
     do they join to goal ids?
  3. Do nodeType 2 nodes really have 4 neighbours (junctions)?
  4. Which wayType numbers are reachable and do their edge rows carry the tools tag?
"""
import io
import json
import os
import collections

BASE = r'H:\AI\frog\work\cdn\live\1020_1021\resource\China\config\TravelData'
GD = r'H:\AI\frog\work\run\engine\data\gamedata.json'


def load(name, table=None):
    if table:
        g = json.loads(io.open(GD, encoding='utf-8').read())['tables']
        v = g[table]
        return list(v.values()) if isinstance(v, dict) else v
    d = json.loads(io.open(os.path.join(BASE, name + '.json'), encoding='utf-8').read())
    if isinstance(d, dict):
        for k in ('data', 'list', 'rows'):
            if k in d:
                return d[k]
        return list(d.values())
    return d


node = load('Node')
conn = {int(r['id']): r for r in load('NodeConnect')}
edges = load('NodeEdge')
goal = load('NodeGoal')
nitem = {int(r['id']): r for r in load('NodeItem')}
pic = load('Picture', 'Picture')
ptag = load('PictureTag', 'PictureTag')

print('=== 1. NodeEdge keying ===')
c = collections.Counter(int(r['id']) for r in edges)
print('   rows=%d distinct ids=%d  ids with >1 row=%d' % (len(edges), len(c), sum(1 for v in c.values() if v > 1)))
print('   multiplicity dist:', dict(collections.Counter(c.values())))
dups = [k for k, v in c.items() if v > 1][:4]
for d in dups:
    rows = [r for r in edges if int(r['id']) == d]
    print('   dup id %s:' % d)
    for r in rows:
        print('      ', json.dumps(r, ensure_ascii=False)[:220])
    print('      node:', json.dumps([r for r in node if int(r['id']) == d][0], ensure_ascii=False))
    print('      conn:', json.dumps(conn.get(d), ensure_ascii=False))

print()
print('=== 2. arrival semantics check: goal nodes vs their edge rows ===')
goal_ids = set(int(r['id']) for r in goal)
byname = {int(r['id']): r.get('name') for r in goal}
for r in node:
    if int(r['id']) in goal_ids:
        i = int(r['id'])
        e = [x for x in edges if int(x['id']) == i]
        print('   goal node %-6s %-10s nodeType=%s pathPoint=%-6s conn=%s' % (i, byname[i], r['nodeType'], r['pathPoint'], conn[i]['edge']))
        for x in (e or [])[:1]:
            print('        edge: wayType=%s time=%s plusTime=%s N=%r T=%r U=%r nPer=%s tPer=%s uPer=%s note=%s' % (
                x['wayType'], x['time'], x['plusTime'], x['NormalTag'], x['ToolsTag'], x['UniqueTag'],
                x['nTagPer'], x['tTagPer'], x['uTagPer'], x['note']))

print()
print('=== 3. nodeType vs neighbour count ===')
for t in (-1, 0, 1, 2, 3):
    lens = collections.Counter(len(conn[int(r['id'])]['edge']) for r in node if r['nodeType'] == t)
    print('   nodeType %-3s n=%-4d neighbour-count dist=%s' % (t, sum(1 for r in node if r['nodeType'] == t), dict(lens)))

print()
print('=== 4. wayType vs tools/unique tags ===')
for wt in sorted(set(x['wayType'] for x in edges)):
    sub = [x for x in edges if x['wayType'] == wt]
    print('   wayType %s n=%-4d ToolsTag sample=%s  UniqueTag sample=%s  time set=%s' % (
        wt, len(sub),
        collections.Counter(x['ToolsTag'] for x in sub).most_common(5),
        collections.Counter(x['UniqueTag'] for x in sub).most_common(5),
        sorted(set(x['time'] for x in sub))[:8]))

print()
print('=== 5. Picture.place / type / PictureTag.tagType ===')
print('   Picture.place:', collections.Counter(r.get('place') for r in pic).most_common(12))
print('   Picture.type :', collections.Counter(r.get('type') for r in pic))
print('   PictureTag.tagType:', collections.Counter(r.get('tagType') for r in ptag))
print('   Goal-type picture samples:')
for r in [x for x in pic if x.get('type') == 'Goal'][:6]:
    print('      id=%-5s name=%-22s place=%s' % (r.get('id'), r.get('name'), r.get('place')))
print('   Goal picture place values:', collections.Counter(r.get('place') for r in pic if r.get('type') == 'Goal'))
print('   Unique picture place values:', collections.Counter(r.get('place') for r in pic if r.get('type') == 'Unique').most_common(8))
print('   Tools picture place values:', collections.Counter(r.get('place') for r in pic if r.get('type') == 'Tools').most_common(8))
print('   Normal picture place values:', collections.Counter(r.get('place') for r in pic if r.get('type') == 'Normal').most_common(8))

print()
print('=== 6. tag -> picture join sanity (n_roof / p_town / u_huabei / g_beijing) ===')
pic_by_name = collections.defaultdict(list)
for r in pic:
    pic_by_name[r.get('name')].append(r)
for tag in ('n_roof', 'p_town', 'u_huabei', 'g_beijing', 'u_rabbit', 'p_dry'):
    rows = [r for r in ptag if r.get('Tag') == tag]
    if not rows:
        print('   %-10s -> NO PictureTag row' % tag)
        continue
    r = rows[0]
    got = []
    for nm in (r.get('picNames') or []):
        for pr in pic_by_name.get(nm, []):
            got.append((pr['id'], pr['type']))
    print('   %-10s id=%-4s type=%-7s picNames=%-58s -> pictures=%s' % (
        tag, r.get('id'), r.get('tagType'), str(r.get('picNames'))[:58], got[:4]))

print()
print('=== 7. nodeItem sample per goal area (what a trip would award) ===')
for r in node:
    if r['nodeType'] == 1:
        i = int(r['id'])
        ni = nitem.get(i, {})
        print('   %-6s %-10s collection=%-5s specialty=%s' % (i, byname[i], ni.get('collection'), list(zip(ni.get('specialtyId') or [], ni.get('specialtyPer') or []))))
