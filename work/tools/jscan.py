#!/usr/bin/env python3
"""Scan binary files for embedded text, trying UTF-8 / CP932 (Shift-JIS) / UTF-16.

Useful for finding Unity TextAssets holding CSV/JSON game data in an APK.

Usage:
  python jscan.py <dir_or_file> [--min N] [--jp] [--csv] [--utf16] [--out FILE]
"""
import os, sys, re, argparse

JP = re.compile(r'[\u3040-\u30ff\u4e00-\u9fff\uff66-\uff9f]')


def runs(data, minlen=4):
    """Yield (offset, text) for plausible text runs, decoded several ways."""
    # ascii/utf8-ish
    for m in re.finditer(rb'[\x09\x0a\x0d\x20-\x7e\x80-\xff]{%d,}' % minlen, data):
        raw = m.group(0)
        yield m.start(), 'raw', raw
    # utf-16le
    for m in re.finditer(rb'(?:[\x09\x0a\x0d\x20-\x7e\u0080-\uffff]\x00){%d,}' % minlen, data):
        yield m.start(), 'u16', m.group(0)


def scan_file(path, minlen, args, out):
    data = open(path, 'rb').read()
    hits = []
    for off, kind, raw in runs(data, minlen):
        cands = []
        if kind == 'raw':
            for enc in ('utf-8', 'cp932'):
                try:
                    cands.append((enc, raw.decode(enc)))
                except UnicodeDecodeError:
                    pass
        else:
            try:
                cands.append(('utf16le', raw.decode('utf-16-le')))
            except UnicodeDecodeError:
                pass
        for enc, txt in cands:
            if args.jp and not JP.search(txt):
                continue
            if args.csv and txt.count(',') < 2:
                continue
            hits.append((off, enc, txt))
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('target')
    ap.add_argument('--min', type=int, default=6)
    ap.add_argument('--jp', action='store_true', help='require Japanese characters')
    ap.add_argument('--csv', action='store_true', help='require >=2 commas')
    ap.add_argument('--out')
    ap.add_argument('--max', type=int, default=200)
    a = ap.parse_args()

    files = []
    if os.path.isfile(a.target):
        files = [a.target]
    else:
        for r, d, fs in os.walk(a.target):
            for f in fs:
                files.append(os.path.join(r, f))
    fh = open(a.out, 'w', encoding='utf-8') if a.out else None
    total = 0
    for f in files:
        try:
            hits = scan_file(f, a.min, a, fh)
        except Exception as e:
            continue
        if not hits:
            continue
        print(f'=== {f}  ({len(hits)} hits)')
        if fh:
            fh.write(f'=== {f}\n')
        for off, enc, txt in hits[:a.max]:
            line = f'  {off:>10} [{enc}] {txt[:400]!r}'
            print(line)
            if fh:
                fh.write(line + '\n')
        total += len(hits)
    print('total hits', total)
    if fh:
        fh.close()


if __name__ == '__main__':
    main()
