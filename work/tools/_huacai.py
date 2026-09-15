from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
items = json.load(open(os.path.join(D,"Item.json"), encoding="utf-8"))
out = open(str(PROJECT_ROOT) + "/work/build/huacai.txt","w",encoding="utf-8")
hc = [i for i in items if i.get("type") == 14 and str(i.get("sub_type")) == "6"]
out.write(f"type14 sub_type6 items: {len(hc)}\n")
for i in hc[:10]:
    out.write(f"   {i['id']}: {i['name']!r} img={i.get('img')}\n")
out.write(f"\nid range {min(i['id'] for i in hc)}..{max(i['id'] for i in hc)}\n")
# also type 3 specialties in the 4101-4104 range the spec mentioned
sp = [i for i in items if i.get("type") == 3 and 4000 <= i["id"] <= 4200]
out.write(f"\ntype3 specialties 4000..4200: {len(sp)}\n")
for i in sp[:8]:
    out.write(f"   {i['id']}: {i['name']!r}\n")
out.close(); print("ok")
