# -*- coding: utf-8 -*-
"""Analyse the archived TravelData tables to recover the walk-graph semantics.

Read-only. Prints set relationships and raw samples so the engine walker can be
written against real joins instead of guesses.
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


def p(*a):
    print(*a)


def main():
    node = load('Node')
    conn = load('NodeConnect')
    edge = load('NodeEdge')
    goal = load('NodeGoal')
    nitem = load('NodeItem')
    area = load('Area')
    pic = load('Picture', 'Picture')
    ptag = load('PictureTag', 'PictureTag')

    p('=== row counts ===')
    for nm, rows in (('Node', node), ('NodeConnect', conn), ('NodeEdge', edge),
                     ('NodeGoal', goal), ('NodeItem', nitem), ('Area', area),
                     ('Picture', pic), ('PictureTag', ptag)):
        p('   %-12s %d' % (nm, len(rows)))

    node_ids = set(int(r['id']) for r in node)
    p()
    p('=== Node field distributions ===')
    p('   id range      :', min(node_ids), '-', max(node_ids))
    p('   nodeType      :', dict(collections.Counter(r.get('nodeType') for r in node)))
    p('   pathPoint     :', dict(collections.Counter(r.get('pathPoint') for r in node)))
    p('   picTag empty  :', sum(1 for r in node if not r.get('picTag')), 'of', len(node))

    p()
    p('=== NodeConnect ===')
    p('   id set == Node id set ?', set(int(r['id']) for r in conn) == node_ids)
    vals = [x for r in conn for x in (r.get('edge') or [])]
    p('   edge value range:', min(vals), '-', max(vals))
    p('   all edge values are node ids ?', set(vals) <= node_ids)
    p('   edge length dist:', dict(collections.Counter(len(r.get('edge') or []) for r in conn)))
    p('   pos keys        :', dict(collections.Counter(k for r in conn for k in (r.get('pos') or {}))))

    p()
    p('=== NodeEdge ===')
    p('   id range      :', min(int(r['id']) for r in edge), '-', max(int(r['id']) for r in edge))
    p('   id set == node ids ?', set(int(r['id']) for r in edge) <= node_ids)
    p('   fields        :', sorted(set(k for r in edge for k in r)))
    for k in ('wayType', 'plusTime', 'nTagPer', 'tTagPer', 'uTagPer', 'enc_per', 'note', 'plug'):
        vals = collections.Counter()
        for r in edge:
            v = r.get(k)
            vals[json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else v] += 1
        p('   %-8s: %s' % (k, dict(list(vals.items())[:8])))

    p()
    p('=== NodeGoal ===')
    p('   fields:', sorted(set(k for r in goal for k in r)))
    p('   id range:', min(int(r['id']) for r in goal), '-', max(int(r['id']) for r in goal))
    for r in goal:
        p('      id=%-4s %-10s itemPer=%s' % (r.get('id'), r.get('name'), r.get('itemPer')))

    p()
    p('=== goal id vs node id / area range ===')
    for r in goal:
        gid = int(r['id'])
        hit = [a for a in area if int(a['StartID']) <= gid <= int(a['EndID'])]
        p('      goal %-4s %-10s -> area %s' % (gid, r.get('name'), [a['name'] for a in hit]))

    p()
    p('=== area -> node ids in range ===')
    for a in area:
        s, e = int(a['StartID']), int(a['EndID'])
        ids = sorted(i for i in node_ids if s <= i <= e)
        p('      %-12s [%5d,%5d] nodes=%-4d sample=%s' % (a['name'], s, e, len(ids), ids[:6]))

    p()
    p('=== samples: node + connect + nodeitem + edge (first 6 of A_NORTH) ===')
    conn_by = {int(r['id']): r for r in conn}
    item_by = {int(r['id']): r for r in nitem}
    edge_by = {int(r['id']): r for r in edge}
    for r in node[:6]:
        i = int(r['id'])
        p('   node  ', json.dumps(r, ensure_ascii=False))
        p('   conn  ', json.dumps(conn_by.get(i), ensure_ascii=False))
        p('   nitem ', json.dumps(item_by.get(i), ensure_ascii=False))
        p('   edge  ', json.dumps(edge_by.get(i), ensure_ascii=False))
        p()

    p()
    p('=== PictureTag vs Picture ===')
    p('   PictureTag fields:', sorted(set(k for r in ptag for k in r)))
    p('   Picture fields   :', sorted(set(k for r in pic for k in r)))
    names = [n for r in ptag for n in (r.get('picNames') or [])]
    p('   picNames total %d distinct %d sample %s' % (len(names), len(set(names)), names[:6]))
    pic_names = set()
    for r in pic:
        for k in ('name', 'resName', 'pic', 'index', 'res'):
            v = r.get(k)
            if isinstance(v, str):
                pic_names.add(v)
            elif isinstance(v, list):
                pic_names.update(x for x in v if isinstance(x, str))
            elif isinstance(v, dict):
                pic_names.update(x for x in v.values() if isinstance(x, str))
    p('   matched picNames against Picture string fields:', len(set(names) & pic_names), 'of', len(set(names)))
    p('   sample Picture rows:')
    for r in pic[:4]:
        p('      ', json.dumps(r, ensure_ascii=False)[:300])
    p('   sample PictureTag rows:')
    for r in ptag[:6]:
        p('      ', json.dumps(r, ensure_ascii=False)[:260])


main()
