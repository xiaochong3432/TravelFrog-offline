#!/usr/bin/env python3
"""Extract embedded UTF-8 / CP932 text blobs from a binary file.

Unity TextAsset payloads are stored as raw bytes, so any data table shipped as
a TextAsset shows up as a long decodable text run. This finds those runs
without needing a full container parser.

Usage:
  python textblobs.py <file> [--min N] [--jp] [--outdir D] [--extract]
"""
import re, sys, os, argparse

# A run of bytes that are printable ASCII, plus any multi-byte UTF-8 sequences.
RUN = re.compile(rb'(?:[\x09\x0a\x0d\x20-\x7e]|[\xc2-\xf4][\x80-\xbf]+){MIN,}')


def blobs(data, minlen):
    rx = re.compile(RUN.pattern.replace(b'{MIN,}', b'{%d,}' % minlen))
    for m in rx.finditer(data):
        raw = m.group(0)
        try:
            txt = raw.decode('utf-8')
        except UnicodeDecodeError:
            continue
        yield m.start(), txt


JP = re.compile(r'[\u3040-\u30ff\u4e00-\u9fff]')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--min', type=int, default=24)
    ap.add_argument('--jp', action='store_true')
    ap.add_argument('--commas', type=int, default=0)
    ap.add_argument('--outdir')
    ap.add_argument('--show', type=int, default=400)
    ap.add_argument('--limit', type=int, default=200)
    a = ap.parse_args()
    data = open(a.file, 'rb').read()
    n = 0
    total = 0
    for off, txt in blobs(data, a.min):
        total += 1
        if a.jp and not JP.search(txt):
            continue
        if a.commas and txt.count(',') < a.commas:
            continue
        n += 1
        if n > a.limit:
            break
        head = txt[:a.show].replace('\n', '\\n')
        print(f'=== off={off} len={len(txt)} lines={txt.count(chr(10))+1}')
        print(head)
        if a.outdir:
            os.makedirs(a.outdir, exist_ok=True)
            open(os.path.join(a.outdir, 'blob_%08d.txt' % off), 'w', encoding='utf-8').write(txt)
    print('total blobs', total, 'shown', n)


if __name__ == '__main__':
    main()
