# -*- coding: utf-8 -*-
"""Build work/run/engine/data/travel.json -- the server-side travel map.

The engine's walker needs the tables the CLIENT never ships (main.min.js has zero
references to TravelData), so everything comes from the archived China CDN copy:

  work/cdn/live/1020_1021/resource/China/config/TravelData/{Area,Node,NodeConnect,
      NodeEdge,NodeGoal,NodeItem}.json
  work/cdn/live/1020_1021/resource/China/config/MainData/Item.json      (effects)

Recovered semantics (see work/spec/travel-album.md and the analysis scripts
analyze_traveldata*.py for the evidence):

  Node        one point: nodeType -1/0 = ordinary, 1 = GOAL (34 of them, matching
              NodeGoal 1:1), 2/3 = junction / special-route points. picTag is set on
              the 34 goal nodes only and equals GoalNumber.tag (g_beijing, g_bwg_*).
  NodeConnect adjacency, keyed by node id: `edge` lists neighbouring node ids.
  NodeEdge    keyed 1:1 by node id, describing ARRIVING at that node: time cost,
              plusTime (special-route surcharge), wayType (0 normal, 1 cave,
              2 sea, 3 mountain -- each family carries exactly one photo tag set:
              p_fuza / p_wet / p_dry), the three photo tags with their weights, the
              encounter (enc_name + enc_per, a TravelFriends key) and up to three
              Note ids.
  NodeGoal    the 34 goals: name + itemPer[13].
  NodeItem    per node: specialtyId/specialtyPer pairs, collection (>= 0 means "a
              souvenir is available here"; the 7xx value itself belongs to a table
              this archive does not contain), decorationId/Per, drop.

  Area        id ranges name the region AND give the value space of the item
              effects AREA_DECIDE / AREA_STEP (A_NORTH, A_WSOUTH, A_HK, ...).

Area -> place (地区名 for Collection/Specialty lookups) is DERIVED from the data:
every goal node's own specialties carry `place`, so the region name is counted
rather than invented.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os
import collections

CFG = str(PROJECT_ROOT) + "/work/cdn/live/1020_1021/resource/China/config"
OUT = str(PROJECT_ROOT) + "/work/run/engine/data/travel.json"
GD = str(PROJECT_ROOT) + "/work/run/engine/data/gamedata.json"


def load(path):
    d = json.loads(io.open(path, encoding='utf-8').read())
    if isinstance(d, dict):
        for k in ('data', 'list', 'rows'):
            if k in d:
                return d[k]
        return list(d.values())
    return d


def main():
    base = os.path.join(CFG, 'TravelData')
    areas = load(os.path.join(base, 'Area.json'))
    nodes = load(os.path.join(base, 'Node.json'))
    conn = load(os.path.join(base, 'NodeConnect.json'))
    edges = load(os.path.join(base, 'NodeEdge.json'))
    goals = load(os.path.join(base, 'NodeGoal.json'))
    nitems = load(os.path.join(base, 'NodeItem.json'))
    items = load(os.path.join(CFG, 'MainData', 'Item.json'))

    g = json.loads(io.open(GD, encoding='utf-8').read())['tables']
    sp = g['Specialty']
    sp = list(sp.values()) if isinstance(sp, dict) else sp
    sp_place = {}
    for r in sp:
        sp_place[int(r['itemId'])] = r.get('place')
    gnum = g['GoalNumber']
    gnum = list(gnum.values()) if isinstance(gnum, dict) else gnum
    tag_place = {}
    for r in gnum:
        tag_place[str(r.get('tag'))] = int(r['id'])

    def area_of(nid):
        for a in areas:
            if int(a['StartID']) <= nid <= int(a['EndID']):
                return int(a['id'])
        return -1

    out_areas = [{'id': int(a['id']), 'name': a['name'],
                  'start': int(a['StartID']), 'end': int(a['EndID']),
                  'place': ''} for a in areas]
    area_by_id = {a['id']: a for a in out_areas}

    # --- area -> place, counted from each goal node's own specialties ------------
    node_by_id = {int(r['id']) for r in nodes}
    goal_rows = []
    for r in goals:
        nid = int(r['id'])
        nm = r.get('name')
        pg = None
        for a in out_areas:
            if a['start'] <= nid <= a['end']:
                pg = a
                break
        goal_rows.append({'node': nid, 'name': nm, 'area': pg['id'] if pg else -1,
                          'itemPer': r.get('itemPer') or []})

    # Only the GOAL nodes vote: a region's own souvenirs are the place-typed rows
    # (京味点心 = 华北地区). Ordinary nodes are full of farm produce (水果/蔬菜/谷物),
    # which would win the vote and name the whole region after a crop.
    goal_node_ids = set(int(r['id']) for r in goals)
    place_votes = collections.defaultdict(collections.Counter)
    for r in nitems:
        nid = int(r['id'])
        if nid not in goal_node_ids:
            continue
        aid = area_of(nid)
        for i in (r.get('specialtyId') or []):
            pl = sp_place.get(int(i))
            if pl and ('地区' in pl or '博物馆' in pl or '博物院' in pl):
                place_votes[aid][pl] += 1
    for aid, votes in place_votes.items():
        if aid in area_by_id:
            area_by_id[aid]['place'] = votes.most_common(1)[0][0]

    # Museums: their own goal's name IS the Specialty.place row (江西省博物馆 ...).
    museum_places = {}
    for r in sp:
        pl = r.get('place') or ''
        if '博物馆' in pl or '博物院' in pl:
            museum_places[pl] = True
    for gr in goal_rows:
        a = area_by_id.get(gr['area'])
        if a and not a['place']:
            if gr['name'] in museum_places:
                a['place'] = gr['name']
            else:
                # 苏州吴文化博物馆 vs the table's 吴文化博物馆: match on containment.
                for pl in museum_places:
                    if pl in gr['name'] or gr['name'] in pl:
                        a['place'] = pl
                        break

    # Remaining regions: the goals' names fix the region, and every one of these
    # names exists as a Collection/Specialty place. This is the only place in the
    # build that is written by hand rather than counted.
    REGION_FALLBACK = {
        'A_SOUTH': '华南地区', 'A_HK': '港澳地区', 'A_ENORTH': '东北地区',
        'A_WSOUTH2': '西南地区',
    }
    for name, place in REGION_FALLBACK.items():
        for a in out_areas:
            if a['name'] == name and not a['place']:
                a['place'] = place

    # --- goals: name / place id / photo tag -------------------------------------
    for r in nitems:
        nid = int(r['id'])
        if any(x['node'] == nid for x in goal_rows):
            continue
    node_pic = {int(r['id']): (r.get('picTag') or '') for r in nodes}
    for gr in goal_rows:
        gr['picTag'] = node_pic.get(gr['node'], '')
        gr['place'] = tag_place.get(gr['picTag'], -1)

    # --- compact tables ---------------------------------------------------------
    out_nodes = {}
    for r in nodes:
        nid = int(r['id'])
        out_nodes[str(nid)] = [int(r.get('nodeType', 0)), int(r.get('pathPoint') or 0),
                               node_pic.get(nid, '')]
    out_conn = {}
    for r in conn:
        out_conn[str(int(r['id']))] = [int(x) for x in (r.get('edge') or [])]
    out_edges = {}
    for r in edges:
        eid = int(r['id'])
        if eid not in node_by_id:
            continue                     # 33 rows describe nodes this build dropped
        note = [int(x) for x in (r.get('note') or [0, 0, 0])]
        out_edges[str(eid)] = {
            't': int(r.get('time') or 0),
            'pt': int(r.get('plusTime') or 0),
            'w': int(r.get('wayType') or 0),
            'n': r.get('NormalTag') or '',
            'p': r.get('ToolsTag') or '',
            'u': r.get('UniqueTag') or '',
            'np': int(r.get('nTagPer') or 0),
            'pp': int(r.get('tTagPer') or 0),
            'up': int(r.get('uTagPer') or 0),
            'en': r.get('enc_name') or '',
            'ep': int(r.get('enc_per') or 0),
            'no': [x for x in note if x],
        }
    out_nitems = {}
    for r in nitems:
        nid = int(r['id'])
        sp_ids = [int(x) for x in (r.get('specialtyId') or [])]
        sp_per = [int(x) for x in (r.get('specialtyPer') or [])]
        dec = [int(x) for x in (r.get('decorationId') or [])]
        out_nitems[str(nid)] = {
            's': [list(x) for x in zip(sp_ids, sp_per)],
            'c': int(r.get('collection') if r.get('collection') is not None else -1),
            'd': dec,
        }
    out_effects = {}
    for r in items:
        eff = [e for e in (r.get('effects') or []) if isinstance(e, dict)]
        if eff:
            out_effects[str(int(r['id']))] = [[e.get('effect'), e.get('effectType'),
                                               e.get('effectValue')] for e in eff]

    data = {
        '_source': 'China CDN 1020_1021 TravelData/* + MainData/Item.json effects; '
                   'see work/tools/build_travel_data.py',
        '_wayType': {'0': 'normal', '1': 'cave', '2': 'sea', '3': 'mountain'},
        '_effect': 'effect = Item.EffectType, effectType = Item.EffectTypeValue; '
                   'area names come from Area.json, tool families from EVT_WAY',
        'areas': out_areas,
        'nodes': out_nodes,
        'connect': out_conn,
        'edges': out_edges,
        'goals': goal_rows,
        'nodeItems': out_nitems,
        'effects': out_effects,
    }
    with io.open(OUT, 'w', encoding='utf-8') as fh:
        fh.write(json.dumps(data, ensure_ascii=False, separators=(',', ':')))

    print('wrote %s (%d bytes)' % (OUT, os.path.getsize(OUT)))
    print('  areas=%d (with place=%d)  nodes=%d  connect=%d  edges=%d  goals=%d  nodeItems=%d  effectItems=%d'
          % (len(out_areas), sum(1 for a in out_areas if a['place']), len(out_nodes),
             len(out_conn), len(out_edges), len(goal_rows), len(out_nitems), len(out_effects)))
    print('  area -> place:')
    for a in out_areas:
        print('     %-12s [%5d,%5d] -> %s' % (a['name'], a['start'], a['end'], a['place'] or '(none)'))
    print('  goals without GoalNumber place id:',
          [(r['node'], r['name'], r['picTag']) for r in goal_rows if r['place'] < 0])
    no_edge = sorted(int(k) for k in out_nodes if k not in out_edges)
    print('  node ids with NO arrival edge row (%d):' % len(no_edge), no_edge[:14], '...' if len(no_edge) > 14 else '')
    missing_edge = [str(r['node']) for r in goal_rows if str(r['node']) not in out_edges]
    print('  goal nodes without an arrival edge row:', missing_edge or 'none')
    print('  sample goal row:', json.dumps(goal_rows[0], ensure_ascii=False))
    print('  sample edge row :', json.dumps(out_edges['1'], ensure_ascii=False))
    print('  sample nodeItem :', json.dumps(out_nitems['0'], ensure_ascii=False))
    print('  effect rows for tools 2000-2002 / ticket 1017 / 四叶草 1000:')
    for k in ('2000', '2002', '1017', '1000'):
        print('     %-5s %s' % (k, json.dumps(out_effects.get(k), ensure_ascii=False)))


main()
