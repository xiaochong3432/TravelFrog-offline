#!/usr/bin/env python3
"""Extract entries from an Egret .eab bundle.

Layout (observed):
  0..8    magic "\x89EAB\r\n\x1a\n"
  8..12   u32 LE = length of the JSON index
  12..    JSON index: [{"n":resourceName,"f":originalPath,"s":size,"t":type}, ...]
  then    entry payloads, concatenated in manifest order
"""
import json, struct, sys, os

def load(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89EAB\r\n\x1a\n", "not an eab"
    (idxlen,) = struct.unpack_from("<I", d, 8)
    man = json.loads(d[12:12 + idxlen].decode("utf8"))
    data_off = 12 + idxlen
    entries = {}
    pos = data_off
    for e in man:
        size = e.get("s", 0)
        entries[e["n"]] = (pos, size, e)
        pos += size
    return d, entries, pos


def main():
    p = sys.argv[1]
    d, entries, end = load(p)
    print(f"{os.path.basename(p)}: {len(d)} bytes, {len(entries)} entries")
    print(f"payload ends at {end} ({'OK' if end == len(d) else 'MISMATCH'})")
    if len(sys.argv) < 3:
        for n, (o, s, e) in entries.items():
            print(f"  {n:<40} off={o:<9} size={s:<9} type={e.get('t')}")
        return
    name = sys.argv[2]
    if name not in entries:
        print("no such entry:", name); return
    o, s, e = entries[name]
    blob = d[o:o + s]
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(
        r"H:\AI\frog\work", "eab_" + name.replace("/", "_"))
    mode = "wb"
    with open(out, mode) as f:
        f.write(blob)
    print(f"wrote {out} ({s} bytes)")
    if e.get("t") == "text" or blob[:1] in (b"{", b"["):
        print("---- first 400 bytes ----")
        print(blob[:400].decode("utf8", "replace"))


if __name__ == "__main__":
    main()
