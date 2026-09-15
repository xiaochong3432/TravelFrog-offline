#!/usr/bin/env python3
"""Minimal Android binary XML (AXML) parser: package, version, permissions, components."""
import struct, sys, os

def parse_string_pool(data, off):
    (typ,) = struct.unpack_from("<H", data, off)
    assert typ == 0x0001, f"expected string pool, got {typ:#x}"
    (hdr_size, size) = struct.unpack_from("<HH", data, off + 2)
    (str_count, style_count, flags, str_start) = struct.unpack_from("<IIII", data, off + 8)
    utf8 = bool(flags & (1 << 8))
    offsets = struct.unpack_from(f"<{str_count}I", data, off + 28)
    base = off + str_start
    out = []
    for o in offsets:
        p = base + o
        if utf8:
            n = data[p]; p += 1
            if n & 0x80:
                n = ((n & 0x7F) << 8) | data[p]; p += 1
            m = data[p]; p += 1
            if m & 0x80:
                m = ((m & 0x7F) << 8) | data[p]; p += 1
            out.append(data[p:p + n].decode("utf8", "replace"))
        else:
            (n,) = struct.unpack_from("<H", data, p); p += 2
            out.append(data[p:p + n * 2].decode("utf-16-le", "replace"))
    return out, hdr_size, size

def parse_axml(path):
    data = open(path, "rb").read()
    print(f"===== {path} ({len(data)} bytes) =====")
    (typ, hdr_size, size) = struct.unpack_from("<HHI", data, 0)
    print(f"file type={typ:#x} hdr={hdr_size} size={size}")
    off = hdr_size
    strings = []
    while off < len(data):
        (ctype,) = struct.unpack_from("<H", data, off)
        (chdr, csize) = struct.unpack_from("<HH", data, off + 2)
        if ctype == 0x0001:
            strings, chdr, csize = parse_string_pool(data, off)
            print(f"string pool: {len(strings)} strings")
        elif ctype == 0x0102:  # START_ELEMENT
            (line,) = struct.unpack_from("<I", data, off + 8)
            (ns_i, name_i) = struct.unpack_from("<ii", data, off + 16)
            (attr_start, attr_size, attr_count) = struct.unpack_from("<HHH", data, off + 24)
            tag = strings[name_i] if 0 <= name_i < len(strings) else f"?{name_i}"
            attrs = {}
            for i in range(attr_count):
                ao = off + 16 + attr_start + i * attr_size
                (ans_i, aname_i, araw_i) = struct.unpack_from("<iii", data, ao)
                vtype = data[ao + 15]
                (vdata,) = struct.unpack_from("<I", data, ao + 16)
                an = strings[aname_i] if 0 <= aname_i < len(strings) else f"?{aname_i}"
                if vtype == 0x03:
                    v = strings[vdata] if vdata < len(strings) else f"?{vdata}"
                elif vtype == 0x12:
                    v = bool(vdata)
                elif vtype == 0x01:
                    v = f"ref:{vdata:#x}"
                else:
                    v = vdata
                attrs[an] = v
            if tag == "manifest":
                print("\n--- manifest attributes ---")
                for k, v in attrs.items():
                    print(f"   {k} = {v}")
            if tag in ("uses-permission", "uses-feature"):
                print(f"   [{tag}] {attrs.get('name')}")
            if tag in ("activity", "service", "receiver", "provider", "application", "meta-data"):
                label = attrs.get("name") or ""
                extra = ""
                if tag == "application":
                    extra = f"  label={attrs.get('label')}"
                if tag == "meta-data":
                    extra = f"  value={attrs.get('value')}"
                print(f"   [{tag}] {label}{extra}")
            if tag == "uses-sdk":
                print(f"   [uses-sdk] {attrs}")
        off += csize
        if csize == 0:
            break

if __name__ == "__main__":
    for p in sys.argv[1:]:
        parse_axml(p)
        print()
