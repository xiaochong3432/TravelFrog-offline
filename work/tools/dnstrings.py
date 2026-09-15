#!/usr/bin/env python3
"""Extract strings from a .NET/Mono assembly WITHOUT a decompiler.

Parses the CLI metadata heaps directly:
  - #Strings heap : type / method / field names
  - #US heap      : user string literals (what `strings` often mangles)
  - #Blob heap    : not decoded, but raw
Also dumps the Constant table (ldc constants on fields) if requested.

Usage:
  python dnstrings.py <asm.dll> [--names] [--us] [--all] [--grep PAT]
"""
import struct, sys, re, argparse


class PE:
    def __init__(self, data):
        self.d = data
        off = struct.unpack_from('<I', data, 0x3C)[0]
        assert data[off:off + 4] == b'PE\0\0', 'not PE'
        coff = off + 4
        nsec, = struct.unpack_from('<H', data, coff + 2)
        optsz, = struct.unpack_from('<H', data, coff + 16)
        optoff = coff + 20
        magic, = struct.unpack_from('<H', data, optoff)
        self.pe32 = (magic == 0x10b)
        # data directories
        ddoff = optoff + (96 if self.pe32 else 112)
        # CLI header = directory index 14
        cli_rva, cli_sz = struct.unpack_from('<II', data, ddoff + 14 * 8)
        secoff = optoff + optsz
        self.secs = []
        for i in range(nsec):
            b = secoff + i * 40
            name = data[b:b + 8].rstrip(b'\0').decode('latin1')
            vsize, vaddr, rsize, raddr = struct.unpack_from('<IIII', data, b + 8)
            self.secs.append((name, vaddr, vsize, raddr, rsize))
        self.cli = self.rva2off(cli_rva)

    def rva2off(self, rva):
        for name, vaddr, vsize, raddr, rsize in self.secs:
            if vaddr <= rva < vaddr + max(vsize, rsize):
                return raddr + (rva - vaddr)
        raise ValueError('bad rva %x' % rva)


def parse(path):
    data = open(path, 'rb').read()
    pe = PE(data)
    md_rva, md_sz = struct.unpack_from('<II', data, pe.cli + 8)
    md = pe.rva2off(md_rva)
    assert data[md:md + 4] == b'BSJB', 'no BSJB'
    vlen, = struct.unpack_from('<I', data, md + 12)
    p = md + 16
    streams = {}
    for _ in range(vlen):
        off, size = struct.unpack_from('<II', data, p)
        p += 8
        end = data.index(b'\0', p, p + 32)
        nm = data[p:end].decode('latin1')
        p = end + 1
        # stream headers are 4-byte aligned RELATIVE TO THE METADATA ROOT
        rel = p - md
        p = md + ((rel + 3) & ~3)
        streams[nm] = (md + off, size)
    # Robustness: if any known heap stream failed to register, locate its
    # header by scanning for the ASCII name (some writers pad oddly).
    for want in ('#~', '#-', '#Strings', '#US', '#GUID', '#Blob'):
        if want in streams:
            continue
        needle = want.encode() + b'\0'
        try:
            pos = data.index(needle, md, md + 1024)
        except ValueError:
            continue
        off, size = struct.unpack_from('<II', data, pos - 8)
        streams[want] = (md + off, size)
    return data, streams


def us_strings(data, base, size):
    out = []
    p = base + 1
    end = base + size
    while p < end:
        b0 = data[p]
        if b0 == 0:
            p += 1
            continue
        if b0 & 0x80 == 0:
            ln = b0
            p += 1
        elif b0 & 0xC0 == 0x80:
            ln = ((b0 & 0x3F) << 8) | data[p + 1]
            p += 2
        else:
            ln = ((b0 & 0x1F) << 24) | (data[p + 1] << 16) | (data[p + 2] << 8) | data[p + 3]
            p += 4
        raw = data[p:p + ln]
        p += ln
        # last byte is a flag byte
        if raw:
            raw = raw[:-1]
        # The #US heap stores UTF-16LE code units (CLI spec II.24.2.4)
        try:
            out.append(raw.decode('utf-16-le'))
        except UnicodeDecodeError:
            out.append(raw.decode('utf-16-le', 'replace'))
    return out


def strings_heap(data, base, size):
    end = base + size
    out = []
    p = base
    while p < end:
        e = data.index(b'\0', p)
        if e > p:
            out.append(data[p:e].decode('utf-8', 'replace'))
        p = e + 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('asm')
    ap.add_argument('--names', action='store_true')
    ap.add_argument('--us', action='store_true')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--grep')
    ap.add_argument('--json')
    a = ap.parse_args()
    data, streams = parse(a.asm)
    do_us = a.us or a.all or not a.names
    do_nm = a.names or a.all
    res = {}
    if do_us and '#US' in streams:
        b, s = streams['#US']
        res['us'] = us_strings(data, b, s)
    if do_nm and '#Strings' in streams:
        b, s = streams['#Strings']
        res['names'] = strings_heap(data, b, s)
    if a.json:
        import json
        json.dump(res, open(a.json, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        print('wrote', a.json, {k: len(v) for k, v in res.items()})
        return
    rx = re.compile(a.grep) if a.grep else None
    for k in ('us', 'names'):
        if k not in res:
            continue
        for s in res[k]:
            if rx is None or rx.search(s):
                print(f'[{k}] {s}')


if __name__ == '__main__':
    main()
