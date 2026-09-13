import json, collections
D = r"H:\AI\frog\work\run\engine\data\tables"
shop = json.load(open(D + r"\shopData.json", encoding="utf-8"))
items = {i["id"]: i for i in json.load(open(D + r"\Item.json", encoding="utf-8"))}
out = open(r"H:\AI\frog\work\build\shop_limits.txt", "w", encoding="utf-8")
lim = [s for s in shop if s.get("limit", 0) > 0]
out.write(f"shopData entries      : {len(shop)}\n")
out.write(f"with limit > 0        : {len(lim)}\n")
out.write(f"id == itemId          : {sum(1 for s in shop if s['id'] == s['itemId'])}/{len(shop)}\n")
out.write(f"ids differing         : {[(s['id'], s['itemId'], s['limit']) for s in shop if s['id'] != s['itemId']][:12]}\n\n")
out.write("limited entries (id, itemId, limit, price, own_num, spend):\n")
for s in lim[:20]:
    it = items.get(s["itemId"], {})
    out.write(f"  id={s['id']:<3} itemId={s['itemId']:<6} limit={s['limit']:<3} price={s['price']:<5} "
              f"own_num={it.get('own_num')!r:<8} spend={it.get('spend')!r:<6} name={s.get('name')}\n")
out.write("\nprice range: %s\n" % sorted(set(s["price"] for s in shop))[:20])
out.write("before_buy non-empty: %d\n" % sum(1 for s in shop if s.get("before_buy")))
out.write("is_hide_before set  : %d\n" % sum(1 for s in shop if s.get("is_hide_before")))
sp = collections.Counter(str(i.get("spend")) for i in items.values())
out.write("item.spend values   : %s\n" % dict(sp))
on = collections.Counter(str(i.get("own_num")) for i in items.values())
out.write("item.own_num values : %s\n" % dict(list(on.items())[:8]))
out.close()
print("written")
