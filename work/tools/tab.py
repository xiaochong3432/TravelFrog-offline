#!/usr/bin/env python3
"""Analyse the tokenised Tabikaeru master-data stream."""
import json, sys, re

PATH = sys.argv[1] if len(sys.argv) > 1 else r'H:\AI\frog\work\jp_apk\tokens.json'
T = json.load(open(PATH, encoding='utf-8'))


def tables():
    starts = [i for i, (k, p, v) in enumerate(T)
              if k == 'S' and isinstance(v, str) and v.endswith('DataBase')]
    starts.append(len(T))
    out = []
    for a, b in zip(starts, starts[1:]):
        out.append((T[a][2], a, b))
    return out


def show(name):
    for nm, a, b in tables():
        if nm == name:
            for k, p, v in T[a:b]:
                print(('S ' if k == 'S' else 'I ') + repr(v))
            return
    print('not found', name)


if __name__ == '__main__':
    if len(sys.argv) > 2:
        show(sys.argv[2])
    else:
        for nm, a, b in tables():
            strs = [v for k, p, v in T[a:b] if k == 'S']
            print(f'{nm:<24} tokens={b-a:<6} strings={len(strs)}')
