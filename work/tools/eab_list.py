#!/usr/bin/env python3
"""List (and optionally extract) entries of an .eab asset bundle.

Format, verified on resource/China/eab/system.eab:
    magic  \\x89EAB\\r\\n\\x1a\\n   (8 bytes)
    u32    index length
    bytes  JSON index: [{"n":name,"f":file,"s":size,"t":type}, ...]
    bytes  payloads, concatenated IN INDEX ORDER

IMPORTANT: `s` is the entry's SIZE, not an offset -- and the payloads sit in the
same order as the index. Proof: sum(s) over all 70 entries is exactly the payload
length (364986), and taking the bytes that way makes every chunk start with a PNG
magic. An earlier note in this repo claimed size = next entry's offset minus this
one, which produced a 65-byte "PNG"; do not go back to that reading.

Usage:
    python tools/eab_list.py resource/China/eab/system.eab year_summary
    python tools/eab_list.py resource/China/eab/system.eab year_summary --out work/extract
"""
import argparse
import json
import os
import struct
import sys

MAGIC = b"\x89EAB\r\n\x1a\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("filter", nargs="?", default="")
    ap.add_argument("--out", default=None)
    ap.add_argument("--limit", type=int, default=40)
    args = ap.parse_args()

    blob = open(args.path, "rb").read()
    if not blob.startswith(MAGIC):
        print("not an .eab (magic mismatch): %r" % blob[:8])
        return 1
    (idx_len,) = struct.unpack_from("<I", blob, len(MAGIC))
    hdr_end = len(MAGIC) + 4 + idx_len
    index = json.loads(blob[len(MAGIC) + 4:hdr_end].decode("utf-8"))
    total = len(blob) - hdr_end
    print("%s: %d entries, header %d bytes, payload %d bytes (sum of sizes %d)"
          % (os.path.basename(args.path), len(index), hdr_end, total,
             sum(e.get("s", 0) for e in index)))
    if sum(e.get("s", 0) for e in index) != total:
        print("!! size sum does not match the payload -- the layout assumption is wrong")

    hits = [e for e in index if args.filter in e.get("n", "")]
    print("matching %r: %d" % (args.filter, len(hits)))
    for e in hits[: args.limit]:
        print("   %-42s t=%-8s size=%-9s %s" % (e.get("n"), e.get("t"), e.get("s"), e.get("f")))

    if args.out and hits:
        os.makedirs(args.out, exist_ok=True)
        off = hdr_end
        for e in index:                       # payloads follow INDEX order
            data = blob[off:off + e["s"]]
            off += e["s"]
            if e in hits:
                name = os.path.basename(e.get("f") or e["n"])
                path = os.path.join(args.out, name)
                with open(path, "wb") as fh:
                    fh.write(data)
                print("   wrote %s (%d bytes, magic %r)" % (path, len(data), data[:4]))
    return 0


if __name__ == "__main__":
    sys.exit(main())

