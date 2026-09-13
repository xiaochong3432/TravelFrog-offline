import json
g = json.load(open(r"H:\AI\frog\work\run\engine\data\gamedata.json", encoding="utf-8"))
print("keys:", list(g.keys()))
print("tables:", len(g["tables"]))
print("items:", len(g["items"]))
print("Item table entries:", len(g["tables"]["Item"]))
print("sample item:", json.dumps(g["tables"]["Item"][0], ensure_ascii=False))
