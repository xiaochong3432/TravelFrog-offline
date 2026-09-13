#!/usr/bin/env python3
"""Walk a Unity binary blob that interleaves 4-byte scalars with length-prefixed
UTF-8 strings (the shape used by Tabikaeru's *DataBase master tables).

At each position:
  * read i32 n
  * if 0 < n < 8192 and the following n bytes decode as clean printable UTF-8,
    emit a STRING token and advance 4 + align4(n)
  * otherwise emit an INT token and advance 4

Usage:
  python walk.py <file> <start> [--end N] [--json out] [--stride]
"""
import struct, sys, re, argparse, json

CLEAN = re.compile(r'^[\x20-\x7e\u3000-\u30ff\u4e00-\u9fff\uFF01-\uFF60\u2010-\u2033]*$')


def walk(data, start, end=None, maxstr=8192, minstr=2):
    if end is None:
        end = len(data)
    p = start
    toks = []
    while p + 4 <= end:
        n, = struct.unpack_from('<i', data, p)
        if minstr <= n < maxstr and p + 4 + n <= end:
            raw = data[p + 4:p + 4 + n]
            try:
                s = raw.decode('utf-8')
            except UnicodeDecodeError:
                s = None
            if s is not None and CLEAN.match(s) and s.strip():
                toks.append(('S', p, s))
                p += 4 + ((n + 3) & ~3)
                continue
        toks.append(('I', p, n))
        p += 4
    return toks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('start', type=int)
    ap.add_argument('--end', type=int)
    ap.add_argument('--json')
    ap.add_argument('--startswith')
    a = ap.parse_args()
    data = open(a.file, 'rb').read()
    toks = walk(data, a.start, a.end)
    if a.json:
        json.dump(toks, open(a.json, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
        print('wrote', a.json, len(toks), 'tokens')
        return
    off = 0
    for kind, p, v in toks:
        if a.startswith and kind == 'S' and not v.startswith(a.startswith):
            continue
        print(f'{p:>10} {kind} {v!r}')


if __name__ == '__main__':
    main()
