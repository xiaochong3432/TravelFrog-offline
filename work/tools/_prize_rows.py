import json, collections
D = r"H:\AI\frog\work\run\engine\data\tables"
prize = json.load(open(D+r"\Prize.json", encoding="utf-8"))
items = {i["id"]: i for i in json.load(open(D+r"\Item.json", encoding="utf-8"))}
out = open(r"H:\AI\frog\work\build\prize_rows.txt","w",encoding="utf-8")
out.write(f"Prize rows: {len(prize)}\n")
out.write(f"stock values: {dict(collections.Counter(str(p.get('stock')) for p in prize))}\n")
out.write("by rank:\n")
byr = collections.defaultdict(list)
for p in prize: byr[p.get("rank")].append(p)
for r in sorted(byr):
    out.write(f"  rank {r} ({len(byr[r])} rows): {[ (p['id'], p['itemId'], p['stock']) for p in byr[r] ]}\n")
out.write("\nrows with itemId < 0: %s\n" % [(p['id'], p['rank'], p['itemId']) for p in prize if p.get('itemId',0) < 0])
out.write("all itemIds exist in Item.json: %s\n" % all(p.get('itemId',-1) < 0 or p['itemId'] in items for p in prize))
out.close(); print("ok")
