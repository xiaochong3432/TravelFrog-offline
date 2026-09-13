from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
en = json.load(open(os.path.join(D,"encyclopedia.json"), encoding="utf-8"))
fp = json.load(open(os.path.join(D,"flowerpotData.json"), encoding="utf-8"))
lst = en["list"]
out = open(str(PROJECT_ROOT) + "/work/build/plantmap.txt","w",encoding="utf-8")
out.write(f"encyclopedia list n={len(lst)}\n")
ok = bad = 0
for pid, p in sorted((int(k), v) for k, v in fp["plant"].items()):
    lid = str(pid - 1000000)
    e = lst.get(lid)
    if not e:
        bad += 1
        out.write(f"  plant {pid} {p['name']!r} -> long_id {lid} NOT FOUND\n")
        continue
    # compare names: plant "角堇·火龙果" should be encyclopedia name+sub_name
    want = f"{e['name']}·{e['sub_name']}"
    match = (want == p["name"])
    ok += 1 if match else 0
    if not match:
        bad += 1
        out.write(f"  plant {pid} {p['name']!r} -> encyc {want!r} MISMATCH\n")
out.write(f"\nmap ok={ok} bad={bad} of 35\n")
# how are species (id) and variants (sub_id) distributed?
ids = sorted({e["id"] for e in lst.values()})
subs = sorted({(e["id"], e["sub_id"]) for e in lst.values()})
out.write(f"distinct species ids: {len(ids)} -> {ids}\n")
out.write(f"distinct (id,sub_id) pairs: {len(subs)}\n")
out.write(f"desc ids: {sorted(int(k) for k in en['desc'])}\n")
out.close(); print("ok")
