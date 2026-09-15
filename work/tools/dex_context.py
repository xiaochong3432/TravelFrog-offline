"""Print readable DEX string-table literals in a window around a byte pattern.

DEX string_data entries are MUTF-8 with a ULEB128 length prefix, laid out
sequentially, so literals that belong to the same code path usually sit near each
other.  This gives a cheap view of the neighbourhood without a full dex parser.

Usage: python dex_context.py <dex> <pattern> [window]
"""
import struct
import sys

path, pat = sys.argv[1], sys.argv[2].encode()
win = int(sys.argv[3]) if len(sys.argv) > 3 else 3000
d = open(path, "rb").read()


def uleb(data, p):
    v, shift = 0, 0
    while True:
        b = data[p]
        v |= (b & 0x7F) << shift
        p += 1
        if not (b & 0x80):
            return v, p
        shift += 7


def dump_window(lo, hi):
    p = lo
    out = []
    while p < hi:
        try:
            n, q = uleb(d, p)
        except IndexError:
            break
        if n == 0 or n > 400 or q + n > len(d):
            p += 1
            continue
        raw = d[q:q + n]
        try:
            s = raw.decode("utf-8")
        except UnicodeDecodeError:
            p += 1
            continue
        if all(31 < ord(c) < 127 or c in "\t" for c in s):
            out.append((p, s))
            p = q + n + 1
        else:
            p += 1
    return out


i = 0
while True:
    i = d.find(pat, i)
    if i < 0:
        break
    print(f"=== {pat.decode()} at offset {i} ===")
    for off, s in dump_window(max(0, i - win), min(len(d), i + win)):
        mark = "  <<<<" if off <= i < off + len(s) + 4 else ""
        print(f"  {off:8d}  {s}{mark}")
    print()
    i += 1
