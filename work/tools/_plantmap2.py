from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
en = json.load(open(os.path.join(D,"encyclopedia.json"), encoding="utf-8"))
fp = json.load(open(os.path.join(D,"flowerpotData.json"), encoding="utf-8"))
lists = list(en["list"].values())
# index by (name, sub_name) and by the display string
bykey = {}
for e in lists:
    bykey[(e["name"], e["sub_name"])] = e
out = open(str(PROJECT_ROOT) + "/work/build/plantmap2.txt","w",encoding="utf-8")
ok = miss = 0
misses = []
for pid, p in sorted((int(k), v) for k, v in fp["plant"].items()):
    nm = p["name"]
    if "·" in nm:
        a, b = nm.split("·", 1)
    else:
        a, b = nm, ""
    e = bykey.get((a, b))
    if e:
        ok += 1
    else:
        miss += 1
        misses.append((pid, nm))
out.write(f"name-based mapping: ok={ok} miss={miss} of 35\n")
for m in misses: out.write(f"   miss {m[0]} {m[1]!r}\n")
# what do the misses look like in the encyclopedia?
out.write("\nencyclopedia distinct species names (first 12): %s\n" % sorted({e['name'] for e in lists})[:12])
out.write("plant species names (first 12): %s\n" % sorted({p['name'].split('·')[0] for p in fp['plant'].values()})[:12])
out.close(); print("ok")
