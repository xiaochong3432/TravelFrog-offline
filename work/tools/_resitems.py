import json, os
D = r"H:\AI\frog\work\run\engine\data\tables"
items = {i["id"]: i for i in json.load(open(os.path.join(D,"Item.json"), encoding="utf-8"))}
out = open(r"H:\AI\frog\work\build\res_items.txt","w",encoding="utf-8")
for cid in (200000, 200001, 200002, 200003, 200004, 200005):
    it = items.get(cid)
    out.write(f"  {cid}: {json.dumps(it, ensure_ascii=False) if it else 'MISSING'}\n")
out.close(); print("ok")
