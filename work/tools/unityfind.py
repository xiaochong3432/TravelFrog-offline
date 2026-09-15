#!/usr/bin/env python3
"""Anchor-based Unity SerializedFile object-table locator.

The first object's data always begins exactly at the file's data_offset, so we
can find the object table by searching for that 4-byte value and walking back.
"""
import struct, sys, os


def read_header(d):
    meta, fsz, ver, dataoff = struct.unpack_from('>IIII', d, 0)
    return dict(meta=meta, fsize=fsz, ver=ver, dataoff=dataoff)


def find_table(d, ntypes_hint=None):
    h = read_header(d)
    dataoff = h['dataoff']
    fsz = len(d)
    needle = struct.pack('<I', dataoff)
    results = []
    for rowoff in (0, 1, 2, 3, -1, -2, -3):
        # row layout: pathID(8) off(4) size(4) typeID(4) [classID(2) if v<16]
        #             destroyed(1) scriptTypeIndex(2)
        for rowextra in (3, 5, 2, 7):
            rowsize = 20 + rowextra
            # row0 off field is at table_start + 4 + 8
            base = 12  # nobj(4) + pathID(8)
            start = 0
            while True:
                i = d.find(needle, start)
                if i < 0:
                    break
                start = i + 1
                tbl = i - base
                if tbl < 16:
                    continue
                try:
                    nobj, = struct.unpack_from('<i', d, tbl - 4)
                except struct.error:
                    continue
                if not (0 < nobj <= 300000):
                    continue
                p = tbl
                rows = []
                ok = True
                for k in range(nobj):
                    if p + 20 > fsz:
                        ok = False
                        break
                    pid, bs, bz, tid = struct.unpack_from('<qIIi', d, p)
                    if bz == 0 or bs < dataoff or bs + bz > fsz or tid < 0 or tid > 10000:
                        ok = False
                        break
                    rows.append((pid, bs, bz, tid))
                    p += rowsize
                if ok and rows:
                    results.append(dict(tbl=tbl, nobj=nobj, rowsize=rowsize,
                                        end=max(o + z for _, o, z, _ in rows),
                                        fsz=fsz,
                                        mono=sum(1 for r in rows if r[3] is not None)))
    return h, results


def main():
    for path in sys.argv[1:]:
        d = open(path, 'rb').read()
        h, res = find_table(d)
        print(os.path.basename(path), h, 'fsize=%d' % len(d))
        seen = set()
        for r in res:
            key = (r['tbl'], r['rowsize'])
            if key in seen:
                continue
            seen.add(key)
            print('   tbl=%-8d nobj=%-7d rowsize=%-3d maxend=%-10d (fsize=%d) %s'
                  % (r['tbl'], r['nobj'], r['rowsize'], r['end'], r['fsz'],
                     'PERFECT' if r['end'] == r['fsz'] else ''))


if __name__ == '__main__':
    main()
