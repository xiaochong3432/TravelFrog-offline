"""Summarise the furniture/decoration tables: shape + a sample row each."""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')

FILES = ['furnitureCommon', 'furnitureShopData', 'furnitureData', 'decoration',
         'compostData', 'pocketData', 'pocketCommonData', 'tumblerData',
         'tumblerPathData', 'benchData']


def summarize(v, depth=0):
    if isinstance(v, dict):
        keys = list(v.keys())
        out = '{dict %d keys: %s}' % (len(keys), keys[:8])
        if keys and depth < 2:
            out += '\n      first: %s' % json.dumps(v[keys[0]], ensure_ascii=False)[:260]
        return out
    if isinstance(v, list):
        out = '[list %d]' % len(v)
        if v and depth < 2:
            out += ' first: %s' % json.dumps(v[0], ensure_ascii=False)[:260]
        return out
    return repr(v)[:180]


for f in FILES:
    p = os.path.join(T, f + '.json')
    if not os.path.exists(p):
        print('%-20s MISSING' % f)
        continue
    d = json.load(open(p, encoding='utf-8'))
    print('=' * 74)
    print('%s.json   (%s, %d)' % (f, type(d).__name__, len(d)))
    if isinstance(d, dict):
        for k in list(d.keys())[:6]:
            print('  %-16s %s' % (k, summarize(d[k])))
    else:
        print('  %s' % summarize(d))
    print()
