import json, os
D = r"H:\AI\frog\work\run\engine\data\tables"
en = json.load(open(os.path.join(D,"encyclopedia.json"), encoding="utf-8"))
out = open(r"H:\AI\frog\work\build\ency.txt","w",encoding="utf-8")
out.write(f"encyclopedia keys: {list(en.keys()) if isinstance(en,dict) else type(en).__name__}\n")
if isinstance(en, dict):
    for k, v in en.items():
        out.write(f"  {k}: {type(v).__name__} n={len(v) if hasattr(v,'__len__') else '?'}\n")
        if isinstance(v, list):
            for e in v[:5]: out.write(f"      {json.dumps(e, ensure_ascii=False)}\n")
        elif isinstance(v, dict):
            for kk in list(v)[:5]: out.write(f"      {kk!r}: {json.dumps(v[kk], ensure_ascii=False)[:220]}\n")
out.close(); print("ok")
