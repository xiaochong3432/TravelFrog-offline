import json
g = json.load(open(r"H:\AI\frog\work\run\engine\data\gamedata.json", encoding="utf8"))
print("top-level keys:", list(g.keys()))
for k, v in g.items():
    if isinstance(v, list):
        print(f"  {k:14s} list[{len(v)}]  sample={v[:4]}")
    elif isinstance(v, dict):
        ks = list(v.keys())
        print(f"  {k:14s} dict[{len(v)}]  sample keys={ks[:6]}")
    else:
        print(f"  {k:14s} {v!r}")
