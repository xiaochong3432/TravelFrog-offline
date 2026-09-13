#!/usr/bin/env python3
"""Read Unity 5.6 SerializedFile objects (Tabikaeru JP assets).

Empirically determined layout for these files (format 17, enableTypeTree=0):
  * the four leading header u32s are BIG-endian, the rest little-endian
  * type entry  = classID(4) stripped(1) scriptTypeIndex(2)
                  [scriptID(16) if classID==114] oldTypeHash(16)  -> 23 / 39 B
  * object row  = pathID(8) byteStart(4) byteSize(4) typeID(4)    -> 20 B
  * byteStart is relative to the file's dataOffset in this build

Usage:
  python uscene.py <file> [--scripts] [--mono] [--idx N] [--raw]
"""
import struct, sys, os, re, argparse

TEXT = (49,)


def parse(path):
    d = open(path, 'rb').read()
    meta, fsz, ver, dataoff = struct.unpack_from('>IIII', d, 0)
    z = d.index(b'\0', 0x14)
    unity = d[0x14:z].decode('latin1')
    p = z + 1
    platform = struct.unpack_from('<i', d, p)[0]; p += 4
    ett = d[p]; p += 1
    ntypes = struct.unpack_from('<i', d, p)[0]; p += 4
    types = []
    for _ in range(ntypes):
        cid = struct.unpack_from('<i', d, p)[0]; p += 4
        stripped = d[p]; p += 1
        sti = struct.unpack_from('<h', d, p)[0]; p += 2
        sid = None
        if cid == 114:
            sid = d[p:p + 16].hex(); p += 16
        p += 16
        types.append(dict(cid=cid, stripped=stripped, sti=sti, sid=sid))
    nobj = struct.unpack_from('<i', d, p)[0]; p += 4
    rows = []
    for i in range(nobj):
        pid = struct.unpack_from('<q', d, p)[0]
        bs, bz = struct.unpack_from('<II', d, p + 8)
        tid = struct.unpack_from('<i', d, p + 16)[0]
        p += 20
        off = dataoff + bs
        if off + bz > fsz:
            off = bs
        rows.append(dict(i=i, pid=pid, rel=bs, off=off, size=bz, tid=tid,
                         cid=types[tid]['cid'] if 0 <= tid < ntypes else -1,
                         sti=types[tid]['sti'] if 0 <= tid < ntypes else -1,
                         sid=types[tid]['sid'] if 0 <= tid < ntypes else None))
    return d, dict(meta=meta, fsz=fsz, ver=ver, dataoff=dataoff, unity=unity,
                   platform=platform, ett=ett, ntypes=ntypes, nobj=nobj,
                   table_start=p - nobj * 20), types, rows


class R:
    def __init__(self, d, p):
        self.d = d; self.p = p

    def i32(self):
        v = struct.unpack_from('<i', self.d, self.p)[0]; self.p += 4; return v

    def str(self):
        n = self.i32()
        if not (0 <= n < 8192):
            raise ValueError('bad strlen %d' % n)
        s = self.d[self.p:self.p + n]
        self.p += n
        r = self.p % 4
        if r:
            self.p += 4 - r
        return s.decode('utf-8', 'replace')


def monobehaviour_ints(d, row, limit=200):
    r = R(d, row['off'])
    try:
        n = r.i32()
        r.p += n
        rr = r.p % 4
        if rr:
            r.p += 4 - rr
    except Exception:
        pass
    out = []
    p = r.p
    end = row['off'] + row['size']
    while p + 4 <= end and len(out) < limit:
        iv = struct.unpack_from('<i', d, p)[0]
        fv = struct.unpack_from('<f', d, p)[0]
        out.append((p, iv, fv))
        p += 4
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--scripts', action='store_true')
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--mono', type=int, help='index into MonoBehaviour rows')
    ap.add_argument('--limit', type=int, default=120)
    a = ap.parse_args()
    d, info, types, rows = parse(a.file)
    print(a.file)
    for k, v in info.items():
        print('  %s = %r' % (k, v))
    ms = [r for r in rows if r['cid'] == 115]
    print('  MonoScripts:', len(ms), 'MonoBehaviours:', sum(1 for r in rows if r['cid'] == 114))
    if a.scripts:
        for r in ms:
            try:
                rr = R(d, r['off'])
                nm = rr.str()
                eo = rr.i32()
                rr.p += 16
                cls = rr.str()
                ns = rr.str()
                asm = rr.str()
            except Exception as ex:
                print('   pb pid=%d %s' % (r['pid'], ex)); continue
            print(f'   sti={r["sti"]:<3} pid={r["pid"]:<6} name={nm!r} cls={ns+"." if ns else ""}{cls} asm={asm}')
    if a.list:
        for r in rows:
            print(f'   i={r["i"]:<4} pid={r["pid"]:<6} off={r["off"]:<9} size={r["size"]:<8} cid={r["cid"]:<5} sti={r["sti"]}')
    if a.mono is not None:
        mbs = [r for r in rows if r['cid'] == 114]
        r = mbs[a.mono]
        print(f'--- MonoBehaviour #{a.mono} pid={r["pid"]} sti={r["sti"]} sid={r["sid"]} off={r["off"]} size={r["size"]}')
        for p, iv, fv in monobehaviour_ints(d, r, a.limit):
            print(f'   {p:>9}  i={iv:<14} f={fv:<16.6g}')


if __name__ == '__main__':
    main()
