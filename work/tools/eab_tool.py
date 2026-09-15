#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Work with an Egret .eab texture bundle: list entries, extract one, replace one.

Layout (observed, matches the client's own loader):
   0..8    magic 89 45 41 42 0d 0a <flag> 0a      flag 0x1a = plain, 0x1b = encrypted
   8..12   u32 LE = length of the JSON index
   12..    JSON index: [{"n":name,"f":path,"s":size,"t":type}, ...]
   then    payloads, concatenated in manifest order

`replace` rewrites ONE entry keeping every other byte identical, which is what a
one-texture fix needs: the client indexes by (name, offset, size) so only that entry's
bytes and size change.

Usage:
  python tools/eab_tool.py list  <bundle.eab> [pattern]
  python tools/eab_tool.py get   <bundle.eab> <name> <out.png>
  python tools/eab_tool.py replace <bundle.eab> <name> <in.png> <out.eab>
"""
import io
import json
import struct
import sys

MAGIC = b"\x89EAB\r\n"


def read_bundle(path):
    raw = open(path, "rb").read()
    if raw[:6] != MAGIC:
        raise SystemExit("not an eab: %r" % raw[:8])
    flag = raw[6]          # 0x1a = plain, 0x1b = encrypted (raw[7] is the trailing \n)
    if flag == 0x1b:
        raise SystemExit("bundle is ENCRYPTED (0x1b); decrypt it first (tools/eab_dec.py)")
    idx_len = struct.unpack_from("<I", raw, 8)[0]
    index = json.loads(raw[12:12 + idx_len].decode("utf-8"))
    data_start = 12 + idx_len
    return raw, index, data_start, flag


def entry_bytes(raw, index, data_start, i):
    off = data_start + sum(e["s"] for e in index[:i])
    return raw[off:off + index[i]["s"]], off


def cmd_list(argv):
    raw, index, data_start, flag = read_bundle(argv[0])
    pat = argv[1] if len(argv) > 1 else ""
    print("bundle %s: flag=0x%02x entries=%d index=%d payload=%d"
          % (argv[0], flag, len(index), 12 + len(index and json.dumps(index) or ""),
             len(raw) - data_start))
    for i, e in enumerate(index):
        if pat and pat not in e.get("n", ""):
            continue
        print("  %-4d %-34s %-8s %8d  %s" % (i, e.get("n"), e.get("t"), e.get("s"), e.get("f", "")))
    return 0


def cmd_get(argv):
    raw, index, data_start, flag = read_bundle(argv[0])
    name = argv[1]
    for i, e in enumerate(index):
        if e.get("n") == name:
            body, off = entry_bytes(raw, index, data_start, i)
            open(argv[2], "wb").write(body)
            print("wrote %s (%d bytes, entry %d @%d) type=%s" % (argv[2], len(body), i, off, e.get("t")))
            return 0
    raise SystemExit("no entry named %r" % name)


def cmd_replace(argv):
    src, name, new_png, dst = argv[0], argv[1], argv[2], argv[3]
    raw, index, data_start, flag = read_bundle(src)
    body = open(new_png, "rb").read()
    hit = None
    for i, e in enumerate(index):
        if e.get("n") == name:
            hit = i
            break
    if hit is None:
        raise SystemExit("no entry named %r" % name)
    old_len = index[hit]["s"]

    # every payload, in manifest order, taken from the ORIGINAL offsets
    payloads = []
    off = data_start
    for e in index:
        payloads.append(raw[off:off + e["s"]])
        off += e["s"]
    payloads[hit] = body

    idx2 = [dict(e) for e in index]
    idx2[hit]["s"] = len(body)
    new_index = json.dumps(idx2, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    old_index_len = struct.unpack_from("<I", raw, 8)[0]
    if len(new_index) > old_index_len:
        raise SystemExit("index grew (%d -> %d bytes); refusing to rewrite blindly"
                         % (old_index_len, len(new_index)))
    # the client reads exactly idx_len bytes and JSON.parse()s them: trailing spaces are fine
    new_index = new_index + b" " * (old_index_len - len(new_index))

    out = raw[:8] + struct.pack("<I", old_index_len) + new_index + b"".join(payloads)
    open(dst, "wb").write(out)
    print("replaced %s: %d -> %d bytes; %s -> %s" % (name, old_len, len(body), src, dst))
    return 0


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    return {"list": cmd_list, "get": cmd_get, "replace": cmd_replace}[cmd](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
