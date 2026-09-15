from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
res = json.load(open(os.path.join(D,"resources.json"), encoding="utf-8"))
pic = json.load(open(os.path.join(D,"Picture.json"), encoding="utf-8"))
out = open(str(PROJECT_ROOT) + "/work/build/layers2.txt","w",encoding="utf-8")
out.write(f"resources: dict of {len(res)} entries\n")
ks = list(res)[:3]
for k in ks: out.write(f"  key={k!r} -> {res[k]!r}\n")
# build basename -> resId
bybase = {}
for k, v in res.items():
    if isinstance(v, str):
        bybase.setdefault(v.split("/")[-1], k)
out.write(f"\nunique basenames: {len(bybase)}\n")
# check every layer name used across ALL pictures
names = set()
for p in pic:
    for f in ("backImage", "frontImage"):
        for n in (p.get(f) or []):
            names.add(n)
out.write(f"layer names across ALL {len(pic)} pictures: {len(names)}\n")
hit = [n for n in names if n in bybase]
miss = sorted(set(names) - set(hit))
out.write(f"resolvable: {len(hit)}/{len(names)}  ({100*len(hit)/max(1,len(names)):.1f}%)\n")
out.write(f"unresolvable ({len(miss)}): {miss[:20]}\n")
out.write("examples: %s\n" % [(n, bybase[n]) for n in sorted(hit)[:6]])
out.close(); print("ok")
