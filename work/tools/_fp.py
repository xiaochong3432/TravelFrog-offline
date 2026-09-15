from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
fp = json.load(open(os.path.join(D,"flowerpotData.json"), encoding="utf-8"))
fl = json.load(open(os.path.join(D,"flowerData.json"), encoding="utf-8"))
items = {i["id"]: i for i in json.load(open(os.path.join(D,"Item.json"), encoding="utf-8"))}
out = open(str(PROJECT_ROOT) + "/work/build/flowerpot.txt","w",encoding="utf-8")
out.write(f"flowerpotData keys: {list(fp.keys())}\n")
pot = fp.get("flowerpot") or {}
out.write(f"flowerpot: {len(pot)}\n")
for k in pot: out.write(f"   {k}: {json.dumps(pot[k], ensure_ascii=False)}\n")
pl = fp.get("plant") or {}
out.write(f"\nplant: {len(pl)} entries; first 6:\n")
for k in list(pl)[:6]:
    out.write(f"   {k}: {json.dumps(pl[k], ensure_ascii=False)}\n")
out.write(f"\nflowerData: {len(fl)}\n")
for k in list(fl)[:5]:
    out.write(f"   {k}: {json.dumps(fl[k], ensure_ascii=False)}\n")
# do plant ids look like item ids?
pids = [int(k) for k in pl]
out.write(f"\nplant id range {min(pids)}..{max(pids)}; in Item.json: {sum(1 for p in pids if p in items)}/{len(pids)}\n")
for p in pids[:5]:
    out.write(f"   plant {p} -> Item: {json.dumps(items.get(p), ensure_ascii=False)[:150]}\n")
out.close(); print("ok")
