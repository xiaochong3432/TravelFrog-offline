#!/usr/bin/env python3
"""Verify the data the visitor (guest) system needs, before implementing."""
import json
import os

D = r"H:\AI\frog\work\run\engine\data\tables"
OUT = r"H:\AI\frog\work\build\guest_data.txt"

char = json.load(open(os.path.join(D, "Character.json"), encoding="utf-8"))
vis = json.load(open(os.path.join(D, "visitors.json"), encoding="utf-8"))
gameplay = json.load(open(os.path.join(D, "gameplay.json"), encoding="utf-8"))
define = json.load(open(r"H:\AI\frog\work\run\engine\data\define.json", encoding="utf-8"))

with open(OUT, "w", encoding="utf-8") as out:
    row = char.get("rowItemId") or []
    data = char.get("data") or []
    out.write(f"Character.rowItemId: {len(row)} entries, range {row[0]}..{row[-1]}\n")
    out.write(f"Character.data     : {len(data)} entries\n")
    for d in data:
        t = d.get("taste")
        out.write(f"  id={d.get('id')} name={d.get('name')!r} taste_len={len(t) if isinstance(t, list) else t}\n")
    # do taste vectors align with rowItemId?
    lens = {len(d.get('taste') or []) for d in data}
    out.write(f"  taste vector lengths seen: {lens}  (rowItemId len {len(row)})\n")
    if data and isinstance(data[0].get("taste"), list):
        vals = sorted(set(data[0]["taste"]))
        out.write(f"  taste value set: {vals}\n")

    out.write(f"\nvisitors keys: {list(vis.keys())}\n")
    pl = vis.get("provinceList") or {}
    out.write(f"provinceList: {len(pl)} provinces\n")
    for k in list(pl)[:3]:
        out.write(f"  {k}: {json.dumps(pl[k], ensure_ascii=False)[:220]}\n")
    al = vis.get("actionList") or {}
    out.write(f"actionList: {len(al)} entries; sample\n")
    for k in list(al)[:3]:
        out.write(f"  {k}: {json.dumps(al[k], ensure_ascii=False)}\n")

    out.write(f"\ngameplay: {json.dumps(gameplay, ensure_ascii=False)}\n")

    s = define.get("scalars", {})
    m = define.get("maps", {})
    out.write("\nDefine (visitor / gift):\n")
    for k in ["FRIEND_VISIT_RNDPER", "FRIEND_VISIT_RNDSEC", "FRIEND_VISIT_COOL",
              "FRIEND_VISIT_ACTCOUNT_MIN", "FRIEND_VISIT_ACTCOUNT_MAX", "FRIEND_RNDPOS_MAX",
              "FRIEND_GIFTBOUNUS_CLOVER", "FRIEND_GIFTBOUNUS_TICKET",
              "FRIEND_GIFTBOUNUS_TICKET_MAX", "FourLeafCloverID", "SPECIALTY_PER"]:
        if k in s:
            out.write(f"  {k} = {s[k]}\n")
    for k in ["FRIEND_GIFTPER_NORMAL", "FRIEND_GIFTPER_RARE", "FRIEND_GIFTFIX", "FRIEND_ITEM_DEBUFF"]:
        if k in m:
            out.write(f"  {k} = {json.dumps(m[k], ensure_ascii=False)}\n")

print(f"wrote {OUT}")
