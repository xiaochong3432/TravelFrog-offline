#!/usr/bin/env python3
"""Extract the game data tables out of the client's config.eab bundle.

The client's resource manifest lists the data tables (shopData, Item, Specialty,
Collection, Prize, Character, Shop, GiftData, lotteryData, ...) as `eab_asset`
entries whose url is `config_eab`, i.e. they all live inside a single bundle.

Earlier notes said config.eab was "encrypted / unreadable" because its magic has a
different last byte than config.eab's siblings. This script parses it for real and
writes the tables out, so the data pipeline is reproducible rather than depending
on leftovers from an exploration session.

Outputs:
  work/run/engine/data/tables/<Name>.json   individual tables (source of truth)
  work/run/engine/data/gamedata.json        combined file the engine loads

Usage: python extract_gamedata2.py [--probe-only]
"""
import json
import os
import struct
import sys

ROOT = r"H:\AI\frog"
WEB = os.path.join(ROOT, "work", "run", "web")
RESDIR = os.path.join(WEB, "resource", "China")
OUTDIR = os.path.join(ROOT, "work", "run", "engine", "data", "tables")
COMBINED = os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json")

# tables we actually need, mapped to the output name we want
WANT = {
    "Item_json": "Item",
    "shopData_json": "shopData",
    "furnitureShopData_json": "furnitureShopData",
    "Specialty_json": "Specialty",
    "Collection_json": "Collection",
    "Prize_json": "Prize",
    "Character_json": "Character",
    "Shop_json": "Shop",
    "GiftData_json": "GiftData",
    "lotteryData_json": "lotteryData",
}


def find_config_eab():
    cands = []
    for dp, _dns, fns in os.walk(RESDIR):
        for fn in fns:
            if fn.lower().endswith(".eab"):
                cands.append(os.path.join(dp, fn))
    for c in cands:
        if os.path.basename(c).lower().startswith("config"):
            return c
    return None


def parse_eab(path):
    d = open(path, "rb").read()
    magic = d[:8]
    (idxlen,) = struct.unpack_from("<I", d, 8)
    idx_raw = d[12:12 + idxlen]
    try:
        man = json.loads(idx_raw.decode("utf8"))
        encrypted = False
    except Exception:
        man = None
        encrypted = True
    return d, magic, idxlen, man, encrypted


def main():
    path = find_config_eab()
    if not path:
        print("config.eab not found under", RESDIR)
        return 1
    print(f"bundle: {path}  ({os.path.getsize(path):,} bytes)")
    d, magic, idxlen, man, encrypted = parse_eab(path)
    print(f"magic        : {magic!r}")
    print(f"index length : {idxlen:,}")
    print(f"index plain  : {not encrypted}")
    if encrypted:
        print("  (index is not plain JSON -- this is why it looked 'unreadable')")
        # the payload area may still be reachable if we can find the table starts
        return 1

    print(f"index entries: {len(man)}")
    data_off = 12 + idxlen
    present = [e.get("n") for e in man]
    print("sample names :", present[:12])

    os.makedirs(OUTDIR, exist_ok=True)
    got = {}
    pos = data_off
    for e in man:
        name = e.get("n", "")
        size = e.get("s", 0)
        payload = d[pos:pos + size]
        pos += size
        if name in WANT:
            try:
                got[WANT[name]] = json.loads(payload.decode("utf-8"))
            except Exception as ex:
                print(f"  !! {name}: {ex}")

    for name, obj in sorted(got.items()):
        n = len(obj) if isinstance(obj, (list, dict)) else "?"
        p = os.path.join(OUTDIR, name + ".json")
        with open(p, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=1)
        print(f"  wrote {name:20s} n={n}")

    missing = set(WANT.values()) - set(got)
    if missing:
        print("  missing tables:", sorted(missing))

    # combined file the engine loads: tables + the flat item list it already had
    combined = {"tables": got}
    items = got.get("Item")
    if isinstance(items, list):
        combined["items"] = [
            {"id": it.get("id"), "type": it.get("type"), "sub_type": it.get("sub_type", "")}
            for it in items
        ]
    with open(COMBINED, "w", encoding="utf-8") as f:
        json.dump(combined, f, ensure_ascii=False, indent=1)
    print(f"\nwrote {COMBINED} ({os.path.getsize(COMBINED):,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
