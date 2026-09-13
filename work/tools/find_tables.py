#!/usr/bin/env python3
"""Find which resource file(s) hold the game data tables.

Searches the whole web resource tree (plain files AND inside .eab bundles) for a
literal marker, so we can re-extract the tables reproducibly instead of relying
on leftovers.

Usage: find_tables.py [marker]
"""
import os
import struct
import sys

WEB = r"H:\AI\frog\work\run\web"
marker = (sys.argv[1] if len(sys.argv) > 1 else "shopData").encode("utf-8")

EAB_MAGIC = b"\x89EAB"


def eab_entries(path):
    """Yield (name, payload) for each entry in an .eab bundle, if readable."""
    d = open(path, "rb").read()
    if d[:4] != EAB_MAGIC:
        return
    try:
        import json
        (idxlen,) = struct.unpack_from("<I", d, 8)
        man = json.loads(d[12:12 + idxlen].decode("utf8"))
    except Exception:
        return
    pos = 12 + idxlen
    for e in man:
        size = e.get("s", 0)
        yield e.get("n", "?"), e.get("f", ""), d[pos:pos + size]
        pos += size


hits = []
for dp, _dns, fns in os.walk(WEB):
    for fn in fns:
        p = os.path.join(dp, fn)
        rel = os.path.relpath(p, WEB).replace("\\", "/")
        try:
            if fn.lower().endswith(".eab"):
                for name, orig, payload in eab_entries(p):
                    if marker in payload:
                        hits.append((rel, f"{name} ({orig})", len(payload)))
            else:
                with open(p, "rb") as f:
                    head = f.read()
                if marker in head:
                    hits.append((rel, "(whole file)", len(head)))
        except Exception as ex:
            print(f"  !! {rel}: {ex}")

print(f"marker {marker!r}: {len(hits)} hit(s)")
for rel, where, size in hits:
    print(f"  {rel}   [{where}]  {size:,} bytes")
