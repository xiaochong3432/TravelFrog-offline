import json, os
D = r"H:\AI\frog\work\run\engine\data\tables"
td = json.load(open(os.path.join(D,"taskData.json"), encoding="utf-8"))
items = {i["id"]: i for i in json.load(open(os.path.join(D,"Item.json"), encoding="utf-8"))}
out = open(r"H:\AI\frog\work\build\taskdata.txt","w",encoding="utf-8")
out.write(f"taskData keys: {list(td.keys())}\n\n")
for k, v in td.items():
    out.write(f"=== {k}  type={type(v).__name__} n={len(v)}\n")
    if isinstance(v, list):
        for e in v[:4]: out.write(f"   {json.dumps(e, ensure_ascii=False)}\n")
    else:
        for kk in list(v)[:4]: out.write(f"   {kk!r}: {json.dumps(v[kk], ensure_ascii=False)[:240]}\n")
    out.write("\n")
# resolve reward ids
names = []
def collect(o, acc):
    if isinstance(o, dict):
        for k2, v2 in o.items():
            if "reward" in str(k2).lower() or "item" in str(k2).lower():
                acc.append(v2)
            collect(v2, acc)
    elif isinstance(o, list):
        for x in o: collect(x, acc)
acc = []
collect(td, acc)
out.write("reward-ish values found: %s\n" % json.dumps(acc[:10], ensure_ascii=False))
out.close(); print("ok")
