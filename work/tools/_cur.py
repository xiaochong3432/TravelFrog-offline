import json
D = r"H:\AI\frog\work\run\engine\data\tables"
items = {i["id"]: i for i in json.load(open(D+r"\Item.json", encoding="utf-8"))}
out = open(r"H:\AI\frog\work\build\currency_check.txt","w",encoding="utf-8")
for cid in (200000, 200001, 200002, 200003):
    out.write(f"  Item.json has {cid}? {cid in items}\n")
out.write(f"\nItem id range: {min(items)}..{max(items)}\n")
out.write("ids >= 200000 in Item.json: %s\n" % sorted(i for i in items if i >= 200000))
# where do the 3000+ specialty ids sit vs the 200000 currency ids
out.write("count of ids in 3000..4104: %d\n" % sum(1 for i in items if 3000 <= i <= 4104))
out.close(); print("ok")
