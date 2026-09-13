import json, os
D = r"H:\AI\frog\work\run\engine\data\tables"
items = json.load(open(os.path.join(D,"Item.json"), encoding="utf-8"))
out = open(r"H:\AI\frog\work\build\huacai.txt","w",encoding="utf-8")
hc = [i for i in items if i.get("type") == 14 and str(i.get("sub_type")) == "6"]
out.write(f"type14 sub_type6 items: {len(hc)}\n")
for i in hc[:10]:
    out.write(f"   {i['id']}: {i['name']!r} img={i.get('img')}\n")
out.write(f"\nid range {min(i['id'] for i in hc)}..{max(i['id'] for i in hc)}\n")
# also type 3 specialties in the 4101-4104 range the spec mentioned
sp = [i for i in items if i.get("type") == 3 and 4000 <= i["id"] <= 4200]
out.write(f"\ntype3 specialties 4000..4200: {len(sp)}\n")
for i in sp[:8]:
    out.write(f"   {i['id']}: {i['name']!r}\n")
out.close(); print("ok")
