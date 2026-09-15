from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
items = {i["id"]: i for i in json.load(open(os.path.join(D,"Item.json"), encoding="utf-8"))}
out = open(str(PROJECT_ROOT) + "/work/build/res_items.txt","w",encoding="utf-8")
for cid in (200000, 200001, 200002, 200003, 200004, 200005):
    it = items.get(cid)
    out.write(f"  {cid}: {json.dumps(it, ensure_ascii=False) if it else 'MISSING'}\n")
out.close(); print("ok")
