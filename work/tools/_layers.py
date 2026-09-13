from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
res = json.load(open(os.path.join(D,"resources.json"), encoding="utf-8"))
pic = json.load(open(os.path.join(D,"Picture.json"), encoding="utf-8"))
out = open(str(PROJECT_ROOT) + "/work/build/layers_feasibility.txt","w",encoding="utf-8")
out.write(f"resources type={type(res).__name__} n={len(res) if hasattr(res,'__len__') else '?'}\n")
sample = res[:3] if isinstance(res, list) else [res[k] for k in list(res)[:3]]
out.write("resources sample:\n")
for s in sample: out.write("  %s\n" % json.dumps(s, ensure_ascii=False)[:300])
# can we map a Picture backImage name like 'sky05' to a resId?
names = set()
for p in pic[:60]:
    for k in ("backImage","frontImage"):
        for n in (p.get(k) or []): names.add(n)
out.write(f"\nnames used by first 60 pictures: {len(names)}\n")
out.write("  %s\n" % sorted(names)[:20])
if isinstance(res, list):
    have = {r.get("name") for r in res if isinstance(r, dict)}
else:
    have = set(res.keys())
hit = [n for n in names if n in have]
out.write(f"\nnames found directly in resources keys: {len(hit)}/{len(names)}\n")
out.write("  missing: %s\n" % sorted(set(names)-have)[:12])
out.write("  hit:     %s\n" % sorted(hit)[:12])
out.close(); print("ok")
