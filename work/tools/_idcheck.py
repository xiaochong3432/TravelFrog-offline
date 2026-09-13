import json
D = r"H:\AI\frog\work\run\engine\data\tables"
items = {i["id"]: i for i in json.load(open(D+r"\Item.json", encoding="utf-8"))}
spec = json.load(open(D+r"\Specialty.json", encoding="utf-8"))
coll = json.load(open(D+r"\Collection.json", encoding="utf-8"))
out = open(r"H:\AI\frog\work\build\id_check.txt","w",encoding="utf-8")
out.write("Collection ids (first 6): %s\n" % [c["id"] for c in coll[:6]])
out.write("Collection (id 3014 exists?) %s\n" % any(c["id"]==3014 for c in coll))
out.write("Collection sample names   : %s\n" % [c["name"] for c in coll[:4]])
out.write("Specialty itemIds (first6): %s\n" % [s["itemId"] for s in spec[:6]])
out.write("Specialty itemId 3020    ? %s\n" % any(s["itemId"]==3020 for s in spec))
out.write("Item 3020 exists? %s   Item 3014 exists? %s\n" % (3020 in items, 3014 in items))
out.write("Item 2066 exists? %s  <- the invented one\n" % (2066 in items))
if 3020 in items: out.write("Item 3020 = %s\n" % items[3020])
if 3014 in items: out.write("Item 3014 = %s\n" % items[3014])
out.close(); print("ok")
