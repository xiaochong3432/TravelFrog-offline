import json, collections
D = r"H:\AI\frog\work\run\engine\data\tables"
shop = json.load(open(D+r"\shopData.json", encoding="utf-8"))
items = {i["id"]: i for i in json.load(open(D+r"\Item.json", encoding="utf-8"))}
prize = json.load(open(D+r"\Prize.json", encoding="utf-8"))
out = open(r"H:\AI\frog\work\build\shop_hazards.txt","w",encoding="utf-8")

kinds = collections.Counter()
for s in shop:
    bb = s.get("before_buy") or []
    if len(bb) >= 2:
        kinds[bb[0]] += 1
out.write(f"before_buy kinds: {dict(kinds)}\n")
for s in shop:
    bb = s.get("before_buy") or []
    if len(bb) >= 2 and bb[0] != "shop":
        out.write(f"  NON-SHOP: slot {s['id']} before_buy={bb} name={s.get('name')!r}\n")

missing = [(s["id"], s["itemId"], s.get("name")) for s in shop if s["itemId"] not in items]
out.write(f"\nshopData itemId NOT in Item.json: {len(missing)} {missing[:8]}\n")

# which Item.json type/sub_type combos are currencies?
res = [(i["id"], i.get("sub_type"), i.get("name")) for i in items.values() if i.get("type") == 14]
out.write(f"\ntype 14 (RESOURCE) count={len(res)}; sub_types={dict(collections.Counter(str(r[1]) for r in res))}\n")
out.write(f"  low-id resources: {[r for r in res if r[0] < 3000][:8]}\n")

ranks = collections.Counter(p.get("rank") for p in prize)
out.write(f"\nPrize ranks present: {dict(ranks)}\n")
out.write(f"Prize itemIds: {[p.get('itemId') for p in prize][:8]}\n")
out.close(); print("ok")
