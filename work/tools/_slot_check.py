import json
D = r"H:\AI\frog\work\run\engine\data\tables"
shop = json.load(open(D + r"\shopData.json", encoding="utf-8"))
items = {i["id"]: i for i in json.load(open(D + r"\Item.json", encoding="utf-8"))}
out = open(r"H:\AI\frog\work\build\shop_slots.txt", "w", encoding="utf-8")
for sid in [0, 1, 2, 3, 4, 9, 10, 22, 27]:
    s = next((x for x in shop if x["id"] == sid), None)
    if not s:
        out.write(f"slot {sid}: MISSING\n"); continue
    it = items.get(s["itemId"], {})
    out.write(f"slot {sid}: itemId={s['itemId']} price={s['price']} limit={s['limit']} "
              f"before_buy={s['before_buy']} is_hide_before={s['is_hide_before']} "
              f"name={s.get('name')!r} | item.spend={it.get('spend')!r} item.own_num={it.get('own_num')!r}\n")
out.write("\nslots with non-empty before_buy:\n")
for s in shop:
    if s["before_buy"]:
        out.write(f"  slot {s['id']:<3} itemId={s['itemId']:<6} limit={s['limit']:<3} before_buy={s['before_buy']} name={s.get('name')!r}\n")
out.close()
print("written")
