"""Pull the errcode table out of the preload_eab bundle.

The client's MessageModel does:
    var t = RES.getRes("errcode_json");  // -> [{code, msg}, ...]
    getErrorInfo(code) -> the row for that code
so the exact code -> message mapping is recoverable, which is what lets us pick
the RIGHT code (e.g. 101 = album full, 102 = gift box full) instead of guessing.
"""
import json
import os
import struct
import re

HERE = os.path.dirname(os.path.abspath(__file__))
CHINA = os.path.join(HERE, '..', 'run', 'web', 'resource', 'China')

# find the preload eab
cands = []
for root, _dirs, files in os.walk(CHINA):
    for f in files:
        if 'eab' in f.lower() or 'preload' in f.lower():
            cands.append(os.path.join(root, f))
print('eab-ish files:')
for c in cands[:20]:
    print('   %s  (%d bytes)' % (os.path.relpath(c, CHINA), os.path.getsize(c)))

MAGIC = b'\x89EAB\r\n\x1a\n'


def parse(path):
    """EAB = magic + u32 index_len + JSON index [{n,f,s,t}] + payloads.

    `t` is the entry TYPE (e.g. 'image'), not a size, so a payload runs from its
    own `s` to the next entry's `s` (last one to EOF)."""
    d = open(path, 'rb').read()
    if d[:8] != MAGIC:
        return None
    k = 8
    (n,) = struct.unpack('<I', d[k:k + 4])
    k += 4
    idx = json.loads(d[k:k + n].decode('utf-8'))
    base = k + n
    ordered = sorted(idx, key=lambda e: int(e.get('s', 0)))
    out = {}
    for i, e in enumerate(ordered):
        off = base + int(e.get('s', 0))
        end = (base + int(ordered[i + 1].get('s', 0))
               if i + 1 < len(ordered) else len(d))
        out[e.get('n')] = d[off:end]
    return out


for path in cands:
    got = parse(path)
    if got is None:
        print('\n%s: not an EAB bundle (magic %r)' % (os.path.basename(path), open(path, 'rb').read(8)))
        continue
    print('\n%s: %d entries' % (os.path.basename(path), len(got)))
    names = [n for n in got if 'err' in str(n).lower()]
    print('  errcode-ish entries: %s' % names)
    for n in names:
        raw = got[n]
        print('  --- %s (%d bytes) ---' % (n, len(raw)))
        for enc in ('utf-8',):
            try:
                txt = raw.decode(enc)
                print(txt[:1200])
                os.makedirs(os.path.join(HERE, '..', 'probe'), exist_ok=True)
                open(os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables',
                                  'errcode.json'), 'w', encoding='utf-8').write(txt)
                print('  -> wrote run/engine/data/tables/errcode.json')
            except Exception as e:
                print('  decode failed: %s' % e)
