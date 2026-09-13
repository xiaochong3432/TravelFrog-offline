import json, os, io, sys
d = r"H:\AI\frog\work\spec"
for f in ["eab_shopData_json", "eab_Item_json", "eab_Specialty_json", "eab_Collection_json"]:
    p = os.path.join(d, f)
    raw = open(p, "rb").read()
    print(f"== {f}  {len(raw)} bytes")
    try:
        txt = raw.decode("utf-8")
        print("   decodes as UTF-8: yes")
    except UnicodeDecodeError as e:
        print("   decodes as UTF-8: NO ->", e)
        txt = raw.decode("gbk", "replace")
        print("   decodes as GBK: yes")
    try:
        obj = json.loads(txt)
    except Exception as e:
        print("   json parse failed:", e); continue
    sample = obj[0] if isinstance(obj, list) else obj
    for k in ("name", "info"):
        if isinstance(sample, dict) and k in sample:
            print(f"   sample {k!r} = {sample[k]!r}")
