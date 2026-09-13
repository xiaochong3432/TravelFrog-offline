#!/usr/bin/env python3
"""Restore the ORIGINAL per-table JSON formatting in the merged config.eab.

Our merge wrote the 8 modified tables with json.dumps(separators=(",",":")), i.e. compact.
The retail tables are pretty-printed, so the merged bundle SHRANK by ~350 KB even though we
added content -- correct, but unexplainable in a diff and needlessly different from the
retail artifact we keep comparing against.

Step 1 detects which serialization reproduces the ORIGINAL blob bytes for each table
(proof, not assumption), then step 2 re-writes the merged bundle with that style.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eab_decrypt as E      # noqa: E402
import eab_encode as ENC     # noqa: E402

ROOT = r"H:\AI\frog"
MERGED = os.path.join(ROOT, "work", "run", "web", "resource", "China", "eab", "config.eab")
BACKUP = os.path.join(ROOT, "work", "merge-backup", "20260912-202751",
                      "resource", "China", "eab", "config.eab")

STYLES = {
    "indent=1": lambda o: json.dumps(o, ensure_ascii=False, indent=1),
    "indent=2": lambda o: json.dumps(o, ensure_ascii=False, indent=2),
    "indent=4": lambda o: json.dumps(o, ensure_ascii=False, indent=4),
    "compact": lambda o: json.dumps(o, ensure_ascii=False, separators=(",", ":")),
}


def load(path):
    man, payload, _ = E.open_bundle(path)
    entries, blobs, pos = [], [], 0
    for it in man:
        entries.append(dict(it))
        blobs.append(payload[pos:pos + it["s"]])
        pos += it["s"]
    return entries, blobs


before_entries, before_blobs = load(BACKUP)
after_entries, after_blobs = load(MERGED)

# Which style reproduces the retail blob? Sample the tables that have real content.
proven = {}
for name, style_fn in STYLES.items():
    ok = 0
    total = 0
    for e, b in zip(before_entries, before_blobs):
        if not e["n"].endswith("_json"):
            continue
        try:
            obj = json.loads(b.decode("utf-8"))
        except Exception:  # noqa: BLE001
            continue
        total += 1
        if style_fn(obj).encode("utf-8") == b:
            ok += 1
    print(f"  style {name:9} reproduces {ok}/{total} retail tables")
    proven[name] = ok

best = max(proven, key=proven.get)
print(f"chosen style: {best} ({proven[best]} tables byte-identical)")
if proven[best] < 5:
    print("no style reproduces the retail tables -- NOT rewriting")
    sys.exit(1)

style_fn = STYLES[best]
written = 0
for i, e in enumerate(after_entries):
    if not e["n"].endswith("_json"):
        continue
    obj = json.loads(after_blobs[i].decode("utf-8"))
    new_blob = style_fn(obj).encode("utf-8")
    if new_blob != after_blobs[i]:
        after_blobs[i] = new_blob
        written += 1
print(f"re-serialized {written} tables")

out = ENC.build(after_entries, after_blobs)
open(MERGED, "wb").write(out)
print(f"merged config.eab: {len(out)} bytes (retail: {os.path.getsize(BACKUP)} bytes)")

# verify: untouched tables still byte-identical to retail, merged ones decode equal
after2_entries, after2_blobs = load(MERGED)
bmap = {e["n"]: b for e, b in zip(before_entries, before_blobs)}
amap = {e["n"]: b for e, b in zip(after2_entries, after2_blobs)}
differing = [k for k in amap if k in bmap and amap[k] != bmap[k]]
print(f"tables differing from retail: {len(differing)} -> {sorted(differing)}")
assert len(differing) == 8, "unexpected set of modified tables"
for k in differing:
    a = json.loads(amap[k].decode("utf-8"))
    b = json.loads(bmap[k].decode("utf-8"))
    assert len(a) >= len(b), f"{k} lost rows"
print("OK: formatting restored, only the 8 intended tables differ")
