import json, os
d = r"H:\AI\frog\work\spec"
out = open(r"H:\AI\frog\work\build\shop_preview.txt", "w", encoding="utf-8")
for f in ["eab_shopData_json", "eab_Item_json", "eab_Specialty_json", "eab_Collection_json", "eab_Prize_json"]:
    p = os.path.join(d, f)
    obj = json.load(open(p, encoding="utf-8"))
    out.write(f"===== {f}  type={type(obj).__name__} n={len(obj)}\n")
    items = obj if isinstance(obj, list) else list(obj.values())
    for e in items[:6]:
        out.write(f"  {json.dumps(e, ensure_ascii=False)}\n")
    out.write("\n")
out.close()
print("written")
