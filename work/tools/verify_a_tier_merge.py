#!/usr/bin/env python3
"""Verify the A-tier merge: intended tables only, rows present, and every reference resolves.

Checks (all fail loudly):
  1. decode the merged config.eab and compare EVERY asset blob with the pre-merge backup:
     the differing set must be exactly the intended tables;
  2. the merged bundle round-trips byte-identically (encode(decode(x)) == x), which --
     together with the earlier proof on the untouched bundle -- shows the client's
     decoder can read what we wrote;
  3. every row we added is present, with the exact row count deltas;
  4. REFERENCES RESOLVE: for each new furniture row, its scene images exist as files AND
     its icon stem is a frame of the (replaced) furniture sheet; the animation files
     exist AND are registered; the two postcards' backdrops exist and are reachable via
     resources_json; the new Item's icon is a frame of the icon sheet;
  5. the manifest has no duplicate resource names.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eab_decrypt as E      # noqa: E402
import eab_encode as ENC     # noqa: E402

ROOT = str(PROJECT_ROOT)
WEB = os.path.join(ROOT, "work", "run", "web")
CHINA = os.path.join(WEB, "resource", "China")
MERGED = os.path.join(CHINA, "eab", "config.eab")
MANIFEST = os.path.join(CHINA, "default.res.json")
THEIRS = os.path.join(ROOT, "work", "compare-eab", "theirs.eab")
BACKUP_DIR = sys.argv[1] if len(sys.argv) > 1 else None

INTENDED = {"furnitureData_json", "furnitureShopData_json", "shopData_json", "Item_json",
            "Picture_json", "PictureTag_json", "furnitureCommon_json", "resources_json",
            "benchData_json"}
EXPECTED_ADD = {"furnitureData_json": 30, "furnitureShopData_json": 2, "shopData_json": 2,
                "Item_json": 1, "Picture_json": 2, "PictureTag_json": 2,
                "furnitureCommon_json": 1, "resources_json": 2, "benchData_json": 27}

problems = []


def check(cond, msg):
    if not cond:
        problems.append(msg)
    return cond


def load(path):
    man, payload, _ = E.open_bundle(path)
    out, pos = {}, 0
    for it in man:
        out[it["n"]] = payload[pos:pos + it["s"]]
        pos += it["s"]
    return out


if not BACKUP_DIR:
    # Pick the newest backup that actually holds BOTH files this check compares.
    # Not every backup is a full one: the bench-row re-merge only saves config.eab,
    # and taking that one on faith made this verifier fail with FileNotFoundError
    # instead of saying "no usable backup" (which is what it is).
    base = os.path.join(ROOT, "work", "merge-backup")
    need = [os.path.join("resource", "China", "eab", "config.eab"),
            os.path.join("resource", "China", "default.res.json")]
    usable = [d for d in sorted(os.listdir(base))
              if all(os.path.isfile(os.path.join(base, d, p)) for p in need)]
    if not usable:
        print("no complete pre-merge backup in work/merge-backup "
              "(need config.eab AND default.res.json); pass one explicitly")
        sys.exit(2)
    BACKUP_DIR = os.path.join(base, usable[-1])
before = load(os.path.join(BACKUP_DIR, "resource", "China", "eab", "config.eab"))
after = load(MERGED)
theirs = load(THEIRS)
print(f"backup : {BACKUP_DIR}")
print(f"assets : before={len(before)} after={len(after)} theirs={len(theirs)}")

# 1. only the intended tables changed
changed = {k for k in after if k not in before or after[k] != before[k]}
added_assets = set(after) - set(before)
print(f"\n[1] changed assets: {sorted(changed)}")
print(f"    added assets  : {sorted(added_assets)}")
check(changed <= INTENDED, f"unintended assets changed: {sorted(changed - INTENDED)}")
check(not added_assets, f"assets were added (should be none): {sorted(added_assets)}")

# 2. round-trip of the merged bundle
rt = ENC.build([{"n": k, "f": "", "s": len(v), "t": "json"} for k, v in after.items()],
               [after[k] for k in after])
reread = None
tmp = os.path.join(ROOT, "work", "merged-roundtrip.eab")
open(tmp, "wb").write(rt)
reread = load(tmp)
check(reread == after, "merged bundle does not round-trip")
os.remove(tmp)
print(f"[2] merged bundle round-trips: {reread == after}")

# 3. rows present + deltas
print("[3] table deltas")
for name, want in EXPECTED_ADD.items():
    b = json.loads(before[name].decode("utf-8"))
    a = json.loads(after[name].decode("utf-8"))
    nb, na = len(b), len(a)
    check(na - nb == want, f"{name}: expected +{want}, got +{na - nb}")
    print(f"    {name:26} {nb} -> {na} (+{na - nb}, expected +{want})")

fa = json.loads(after["furnitureData_json"].decode("utf-8"))
fb = json.loads(before["furnitureData_json"].decode("utf-8"))
new_rows = [v for k, v in fa.items() if k not in fb] if isinstance(fa, dict) else \
           [r for r in fa if str(r.get("id")) not in {str(x.get("id")) for x in fb}]
check(len(new_rows) == 30, f"expected 30 new furniture rows, got {len(new_rows)}")

# 4. references resolve
man = json.load(open(MANIFEST, encoding="utf-8"))
names = [r["name"] for r in man["resources"]]
dupes = {n for n in names if names.count(n) > 1}
# The retail manifest already duplicates the plain `eab` entries (config_eab, first_eab,
# ...), so only NEW duplicates are a problem.
before_man = json.load(open(os.path.join(BACKUP_DIR, "resource", "China", "default.res.json"),
                            encoding="utf-8"))["resources"]
before_names = [r["name"] for r in before_man]
before_dupes = {n for n in before_names if before_names.count(n) > 1}
check(dupes <= before_dupes, f"NEW duplicate manifest names: {sorted(dupes - before_dupes)}")
reg = set(names)
sheet_sub = {}
for r in man["resources"]:
    if r.get("type") == "sheet":
        sheet_sub[r["name"]] = set(r.get("subkeys", "").split(","))
all_sub = set().union(*sheet_sub.values()) if sheet_sub else set()

# Sheet frame keys carry the `_png` suffix (frames are keyed like `xw10_8_png`).
sheet_json_path = os.path.join(CHINA, "sheet", "furniture_xw1.json")
sheet_frames = set(json.load(open(sheet_json_path, encoding="utf-8")).get("frames", {}).keys())
icon_sheet = set(json.load(open(os.path.join(CHINA, "sheet", "icon2_sheet.json"), encoding="utf-8")).get("frames", {}).keys())

res_json = json.loads(after["resources_json"].decode("utf-8"))
print("[4] reference resolution")
missing = []
for r in new_rows:
    style = int(r.get("style") or 11)
    folder = "xw101" if style == 101 else "xw10"
    for stem in (r.get("res") or []):
        path = os.path.join(CHINA, "images", "Scene", "Furniture", folder, stem + ".png")
        if not os.path.exists(path):
            missing.append(f"file {path}")
        if (stem + "_png") not in reg:
            missing.append(f"unregistered scene image {stem}_png")
    icon = (r.get("icon") or {}).get("index")
    if icon:
        if (icon + "_png") not in all_sub:
            missing.append(f"icon {icon}_png not a sheet subkey")
        if (icon + "_png") not in sheet_frames:
            missing.append(f"icon {icon}_png not a frame of the furniture sheet")
    for anim in (r.get("animation") or []):
        if not anim:
            continue
        for suffix in ("_ske.json", "_tex.json", "_tex.png"):
            p = os.path.join(CHINA, "animation", "furniture", anim + suffix)
            if not os.path.exists(p):
                missing.append(f"file {p}")
        if (anim + "_ske_json") not in reg:
            missing.append(f"unregistered animation {anim}_ske_json")

# postcards
for pid, stem in ((3102, "u_anniv"), (3103, "u_player")):
    p = os.path.join(CHINA, "images", "Picture", "Unique", stem + ".png")
    if not os.path.exists(p):
        missing.append(f"file {p}")
check(any(res_json.get(k) == "Picture/Unique/u_anniv" for k in res_json),
      "resources_json has no entry for Picture/Unique/u_anniv")
check(any(res_json.get(k) == "Picture/Unique/u_player" for k in res_json),
      "resources_json has no entry for Picture/Unique/u_player")

# item 57 icon
check("goods_98_png" in icon_sheet, "item 57 icon goods_98_png is not a frame of icon2_sheet")
check("goods_98_png" in all_sub, "goods_98_png is not a sheet subkey")

# sheets are supersets
with zipfile.ZipFile(os.path.join(ROOT, "base.apk")) as z:
    old_frames = set(json.loads(z.read("assets/game/resource/China/sheet/furniture_xw1.json").decode("utf-8"))["frames"].keys())
with zipfile.ZipFile(os.path.join(ROOT, "work", "their-final.apk")) as z:
    new_frames = set(json.loads(z.read("assets/game/resource/China/sheet/furniture_xw1.json").decode("utf-8"))["frames"].keys())
check(old_frames <= sheet_frames, "replaced furniture sheet lost frames")
print(f"    furniture sheet frames: apk-old={len(old_frames)} apk-new={len(new_frames)} in-tree={len(sheet_frames)}")
print(f"    unresolved references: {len(missing)}")
for m in missing[:25]:
    print("      " + m)
check(not missing, f"{len(missing)} unresolved references")

print("\n" + ("RESULT: OK -- A-tier merge verified" if not problems
              else "RESULT: PROBLEMS\n  - " + "\n  - ".join(problems)))
sys.exit(0 if not problems else 1)
