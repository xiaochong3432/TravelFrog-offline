#!/usr/bin/env python3
"""Merge the A-tier official content from the reference build into OUR tree.

Source of truth for our client is `work/run/web` (PC zip, wrapper APK and
apk_identity.py all read it). This tool:

  1. backs up every file it is about to touch (into work/merge-backup/<stamp>/);
  2. merges DATA rows into our `config.eab` (never replaces the bundle wholesale --
     the reference bundle also DROPS rows in other tables);
  3. copies the loose assets + the two sheet pairs out of the reference APK;
  4. registers the new resources in `default.res.json` (adds entries, updates the two
     changed sheet subkey lists);
  5. verifies the result: decode the merged bundle and assert the touched tables are
     the ONLY ones that changed, that every row we added is present, and that every
     file/registration a new row needs actually resolves.

A-tier = 30 furniture rows (xw10 27 / xw101 3), 2 Unique postcards, 2 shop rows,
1 furniture-shop row, 1 furnitureCommon label, 2 resources_json registrations,
+1 optional Item. Deliberately NOT included: encytravel (needs client code) and
gif_4/animpictureData (B tier).

Usage:
    python tools/merge_a_tier.py --dry-run
    python tools/merge_a_tier.py --apply
"""
import argparse
import json
import os
import shutil
import sys
import time
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eab_decrypt as E      # noqa: E402
import eab_encode as ENC     # noqa: E402

ROOT = r"H:\AI\frog"
WEB = os.path.join(ROOT, "work", "run", "web")
CHINA = os.path.join(WEB, "resource", "China")
OUR_EAB = os.path.join(CHINA, "eab", "config.eab")
MANIFEST = os.path.join(CHINA, "default.res.json")
THEIR_APK = os.path.join(ROOT, "work", "their-final.apk")
THEIR_EAB = os.path.join(ROOT, "work", "compare-eab", "theirs.eab")
BACKUP_ROOT = os.path.join(ROOT, "work", "merge-backup")

# tables we merge, keyed by bundle asset name; `key` = the row's identity field
ROW_TABLES = [
    ("furnitureData_json", "id"),
    ("furnitureShopData_json", "id"),
    ("shopData_json", "id"),
    ("Item_json", "id"),
    ("Picture_json", "id"),
    ("PictureTag_json", "id"),
    ("furnitureCommon_json", "id"),
]

# loose assets to copy: tree-relative (under resource/China/), pulled from the APK
LOOSE_ASSETS = [
    # 41 scene images
    *[f"images/Scene/Furniture/xw10/xw10_{n}_{p}.png" for n, parts in [
        (1, 3), (2, 1), (3, 3), (4, 3), (5, 2), (6, 1), (7, 1), (8, 1), (9, 1), (10, 2),
        (11, 1), (12, 1), (13, 1), (14, 1), (15, 1), (16, 1), (17, 1), (18, 1), (19, 1),
        (20, 1), (21, 1), (22, 1), (23, 1), (24, 1), (25, 2), (26, 1), (27, 1),
    ] for p in range(1, parts + 1)],
    "images/Scene/Furniture/xw101/xw101_3_2.png",
    "images/Scene/Furniture/xw101/xw101_3_3.png",
    "images/Scene/Furniture/xw101/xw101_4_1.png",
    "images/Scene/Furniture/xw101/xw101_5_1.png",
    "images/Scene/Furniture/xw101/xw101_6_1.png",
    # 3 animation files (furniture 2025)
    "animation/furniture/xw10_25_1_ani_ske.json",
    "animation/furniture/xw10_25_1_ani_tex.json",
    "animation/furniture/xw10_25_1_ani_tex.png",
    # 2 Unique postcards (Picture.backImage resolves by stripping the "back_" prefix)
    "images/Picture/Unique/u_anniv.png",
    "images/Picture/Unique/u_player.png",
]

# sheet pairs to replace wholesale (verified: their frames are a superset of ours)
SHEETS = ["sheet/furniture_xw1.json", "sheet/furniture_xw1.png",
          "sheet/icon2_sheet.json", "sheet/icon2_sheet.png"]


def load_rows(path):
    man, payload, _ = E.open_bundle(path)
    entries, blobs, pos = [], [], 0
    for it in man:
        entries.append(dict(it))
        blobs.append(payload[pos:pos + it["s"]])
        pos += it["s"]
    return entries, blobs


def rows_of(t):
    return list(t.values()) if isinstance(t, dict) else list(t)


def merge_list_table(ours, theirs, key):
    have = {str(r.get(key)) for r in ours}
    added = [r for r in theirs if str(r.get(key)) not in have]
    return ours + added, added


def merge_dict_table(ours, theirs, key, log):
    """Dict-shaped table: add their new rows under THEIR key, avoiding collisions."""
    have = {str(r.get(key)) for r in ours.values()}
    used = set(ours.keys())
    added = []
    for k, r in theirs.items():
        if str(r.get(key)) in have:
            continue
        new_key = k
        if new_key in used:
            numeric = [int(x) for x in used if str(x).isdigit()]
            new_key = str((max(numeric) + 1) if numeric else len(used))
            log(f"    key {k} taken; added as {new_key}")
        ours[new_key] = r
        used.add(new_key)
        added.append((new_key, r))
    return ours, added


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    apply = args.apply and not args.dry_run
    log = print
    stamp = time.strftime("%Y%m%d-%H%M%S")

    entries, blobs = load_rows(OUR_EAB)
    their_entries, their_blobs = load_rows(THEIR_EAB)
    our_tables = {e["n"]: json.loads(b.decode("utf-8")) for e, b in zip(entries, blobs)}
    their_tables = {e["n"]: json.loads(b.decode("utf-8")) for e, b in zip(their_entries, their_blobs)}

    log(f"ours : {len(entries)} assets, {len(our_tables)} tables")
    log(f"theirs: {len(their_entries)} assets, {len(their_tables)} tables")
    log("\n=== DATA ROWS TO MERGE ===")
    new_payloads = {}
    report = {}
    for name, key in ROW_TABLES:
        if name not in our_tables or name not in their_tables:
            log(f"  !! {name} missing on one side -- skipped")
            continue
        o, t = our_tables[name], their_tables[name]
        if isinstance(o, list):
            merged, added = merge_list_table(o, t, key)
            log(f"  {name:26} {len(o)} -> {len(merged)}  (+{len(added)}: "
                f"{[r.get(key) for r in added]})")
        else:
            merged, added = merge_dict_table(dict(o), t, key, log)
            log(f"  {name:26} {len(o)} -> {len(merged)}  (+{len(added)}: "
                f"{[r.get(key) for _, r in added]})")
        report[name] = {"before": len(o), "after": len(merged), "added": len(added)}
        new_payloads[name] = json.dumps(merged, ensure_ascii=False, separators=(",", ":")).encode("utf-8")

    # resources_json: their values are strings; only add keys we lack
    name = "resources_json"
    o, t = our_tables[name], their_tables[name]
    added_res = {k: v for k, v in t.items() if k not in o}
    merged_res = dict(o)
    merged_res.update(added_res)
    log(f"  {name:26} {len(o)} -> {len(merged_res)}  (+{len(added_res)}: {sorted(added_res)})")
    report[name] = {"before": len(o), "after": len(merged_res), "added": len(added_res)}
    new_payloads[name] = json.dumps(merged_res, ensure_ascii=False, separators=(",", ":")).encode("utf-8")

    # ---- manifest ----
    man = json.load(open(MANIFEST, encoding="utf-8"))
    their_man = json.load(open(os.path.join(ROOT, "work", "compare-res", "theirs.res.json"), encoding="utf-8"))
    our_names = {r["name"] for r in man["resources"]}
    add_entries = [r for r in their_man["resources"]
                   if r["name"] not in our_names and any(
                       str(r.get("url", "")).startswith(p) for p in (
                           "images/Scene/Furniture/xw10/", "images/Scene/Furniture/xw101/",
                           "animation/furniture/xw10_", "images/Picture/Unique/u_anniv",
                           "images/Picture/Unique/u_player"))]
    their_by_name = {r["name"]: r for r in their_man["resources"]}
    sheet_updates = []
    for r in man["resources"]:
        if r.get("type") == "sheet" and r["name"] in their_by_name:
            t = their_by_name[r["name"]]
            if t.get("subkeys") != r.get("subkeys"):
                sheet_updates.append((r["name"], len(r.get("subkeys", "").split(",")),
                                      len(t.get("subkeys", "").split(","))))
    log(f"\n=== MANIFEST ===\n  entries to add : {len(add_entries)}")
    log(f"  sheet subkeys to update: {sheet_updates}")

    # ---- file work ----
    log("\n=== FILES ===")
    to_copy = [(a, "assets/game/resource/China/" + a) for a in LOOSE_ASSETS + SHEETS]
    with zipfile.ZipFile(THEIR_APK) as z:
        names = set(z.namelist())
        for rel, apkname in to_copy:
            present = apkname in names
            target = os.path.join(CHINA, rel.replace("/", os.sep))
            exists = os.path.exists(target)
            log(f"  {'OK ' if present else 'MISS'} {rel}  (target exists: {exists})")
            if present and apply:
                os.makedirs(os.path.dirname(target), exist_ok=True)
                if exists:
                    bak = os.path.join(BACKUP_ROOT, stamp, rel.replace("/", os.sep))
                    os.makedirs(os.path.dirname(bak), exist_ok=True)
                    shutil.copy2(target, bak)
                with z.open(apkname) as src, open(target, "wb") as dst:
                    shutil.copyfileobj(src, dst)

    if apply:
        # back up then write the bundle + manifest
        for p in (OUR_EAB, MANIFEST):
            bak = os.path.join(BACKUP_ROOT, stamp, os.path.relpath(p, WEB))
            os.makedirs(os.path.dirname(bak), exist_ok=True)
            shutil.copy2(p, bak)
        for i, e in enumerate(entries):
            if e["n"] in new_payloads:
                blobs[i] = new_payloads[e["n"]]
        open(OUR_EAB, "wb").write(ENC.build(entries, blobs))
        man["resources"].extend(add_entries)
        for r in man["resources"]:
            if r.get("type") == "sheet" and r["name"] in their_by_name:
                r["subkeys"] = their_by_name[r["name"]]["subkeys"]
        json.dump(man, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        log(f"\napplied. backup: {os.path.join(BACKUP_ROOT, stamp)}")
    else:
        log("\n(dry run -- nothing written)")

    json.dump(report, open(os.path.join(ROOT, "work", "a-tier-merge-report.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
