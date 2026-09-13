#!/usr/bin/env python3
"""Produce a clean JSON dump of the Tabikaeru master-data tables.

Reads the tokenised stream produced by walk.py and re-segments it into the
named *DataBase tables.
"""
import json, sys, re

TOK = r'H:\AI\frog\work\jp_apk\tokens.json'
OUT = r'H:\AI\frog\work\jp_apk\tables.json'
T = json.load(open(TOK, encoding='utf-8'))

starts = [i for i, (k, p, v) in enumerate(T)
          if k == 'S' and isinstance(v, str) and v.endswith('DataBase')]
names = [T[i][2] for i in starts]
starts.append(len(T))

res = {}
for nm, a, b in zip(names, starts, starts[1:]):
    seg = T[a:b]
    head = seg[1][2] if len(seg) > 1 and seg[1][0] == 'I' else None
    # keep an ordered token list, strings as {"s":...}
    items = []
    for k, p, v in seg[1:]:
        items.append({'s': v} if k == 'S' else {'i': v})
    res[nm] = {'header_int': head, 'tokens': items}

json.dump(res, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('wrote', OUT)
for nm in names:
    seg = res[nm]['tokens']
    strs = [t['s'] for t in seg if 's' in t]
    print(f'{nm:<24} header={res[nm]["header_int"]!s:<8} tokens={len(seg):<6} strings={len(strs)}')
