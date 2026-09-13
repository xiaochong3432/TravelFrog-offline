"""
Repair work/run/engine/index.js after a PowerShell text round-trip replaced the
TRAILING BYTE of certain 3-byte UTF-8 sequences with an ASCII '?'.

Diagnosis (not a guess -- the byte pattern is unambiguous):
    every damaged site is  <0xE0-0xEF> <0x80-0xBF> '?'   where the '?' sits
    exactly in the third byte of a 3-byte character.  e.g.
        right:  e3 80 8b   = U+300B 》
        broken: e3 80 3f   = "《...?"

So the original character is fully determined by the first two bytes plus one
unknown byte in 0x80..0xBF (64 candidates).  We pick the candidate by matching
the surrounding context against REFFILE, which is a byte-identical-by-
construction copy of the same source produced before the corruption.

Usage: python repair_engine_js.py <broken.js> <reference> [out.js]
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import sys
import os

BROKEN = sys.argv[1] if len(sys.argv) > 1 else str(PROJECT_ROOT) + "/work/run/engine/index.js"
REF = sys.argv[2] if len(sys.argv) > 2 else str(PROJECT_ROOT) + "/work/run/web/__offline-engine.js"
OUT = sys.argv[3] if len(sys.argv) > 3 else BROKEN + '.repaired'

raw = open(BROKEN, 'rb').read()
ref = open(REF, 'rb').read().decode('utf-8', errors='replace')


def find_sites(buf):
    """Yield (offset, nbytes, prefix_bytes) for every truncated 3/4-byte char."""
    out = []
    i = 0
    while i < len(buf):
        b = buf[i]
        if b < 0x80:
            i += 1
            continue
        if 0xC0 <= b < 0xE0:
            n = 2
        elif 0xE0 <= b < 0xF0:
            n = 3
        elif 0xF0 <= b < 0xF8:
            n = 4
        else:
            i += 1
            continue
        seq = buf[i:i + n]
        try:
            seq.decode('utf-8')
            i += n
            continue
        except Exception:
            pass
        # valid lead bytes followed by a '?' in the final position?
        good = 0
        for k in range(1, n - 1):
            if 0x80 <= seq[k] < 0xC0:
                good += 1
            else:
                break
        if good == n - 2 and len(seq) == n and seq[-1] == 0x3F:
            out.append((i, n, seq[:-1]))
            i += n
        else:
            out.append((i, n, None))
            i += 1
    return out


sites = find_sites(raw)
fixable = [s for s in sites if s[2] is not None]
unfixable = [s for s in sites if s[2] is None]
print('damaged sites : %d' % len(sites))
print('  fixable     : %d  (truncated 3/4-byte chars)' % len(fixable))
print('  unfixable   : %d  (some other corruption)' % len(unfixable))
for off, n, _ in unfixable[:10]:
    print('    UNFIXABLE at %d: %r' % (off, raw[max(0, off - 30):off + 20]))

out = bytearray(raw)
repaired = 0
ambiguous = 0
unmatched = 0
report = []

# Sites the context search could not pin down because the reference stores the
# same text in a different container (JSON table vs JS regex literal).  Each one
# was identified from its own bytes and confirmed against the reference: all
# four are U+4E2A 个 in "<thing>超过<N>个", verified by the byte that FOLLOWS
# them (a closing quote, a comma, or the '/' ending the regex literal).
MANUAL = {
    (45758, 'e4b8'): '\u4e2a',
    (45736, 'e4b8'): '\u4e2a',
    (40514, 'e4b8'): '\u4e2a',
    (5028, 'e4b8'): '\u4e2a',
}

# Walk sites back-to-front so earlier offsets stay valid as we splice in text.
for off, n, prefix in reversed(fixable):
    ctx = raw[max(0, off - 40):off]
    # progressively longer context until the reference match is unambiguous
    chosen = None
    for back in range(6, len(ctx) + 1):
        needle = ctx[len(ctx) - back:]
        try:
            hay = needle.decode('utf-8')
        except Exception:
            continue
        idxs = []
        start = 0
        while True:
            k = ref.find(hay, start)
            if k < 0:
                break
            idxs.append(k)
            start = k + 1
            if len(idxs) > 4:
                break
        if not idxs:
            continue
        cands = set()
        for k in idxs:
            ch = ref[k + len(hay):k + len(hay) + 1]
            if not ch:
                continue
            cb = ch.encode('utf-8')
            if len(cb) == n and cb[:-1] == prefix:
                cands.add(ch)
        if len(cands) == 1:
            chosen = cands.pop()
            break
        if len(cands) > 1:
            ambiguous += 1
            break
    if chosen is None:
        m = MANUAL.get((off, prefix.hex()))
        if m is not None:
            out[off:off + n] = m.encode('utf-8')
            repaired += 1
            continue
        unmatched += 1
        report.append(('UNRESOLVED', off, prefix.hex()))
        continue
    out[off:off + n] = chosen.encode('utf-8')
    repaired += 1

print('repaired      : %d' % repaired)
print('unresolved    : %d' % unmatched)
print('ambiguous     : %d' % ambiguous)
for r in report[:10]:
    print('   ', r)

try:
    txt = bytes(out).decode('utf-8')
    print('RESULT decodes as UTF-8: OK (%d chars)' % len(txt))
except Exception as e:
    print('RESULT STILL BROKEN: %s' % e)
    sys.exit(1)

open(OUT, 'w', encoding='utf-8', newline='').write(txt)
print('wrote %s' % OUT)
