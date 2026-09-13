from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
items = json.load(open(os.path.join(D,"Item.json"), encoding="utf-8"))
names = [i["name"] for i in items]
out = open(str(PROJECT_ROOT) + "/work/build/ach_missing.txt","w",encoding="utf-8")
for probe in ["苏州西瓜子","蜜柑","桃子","莜面"]:
    hits = [ (i["id"], i["name"]) for i in items if probe in i["name"] or i["name"] in probe ]
    out.write(f"{probe!r}: exact={probe in names}  near={hits[:6]}\n")
out.write("\n--- items whose name contains 瓜子 / 柑 / 桃 / 莜 ---\n")
for kw in ["瓜子","柑","桃","莜"]:
    hits = [(i["id"], i["name"]) for i in items if kw in i["name"]]
    out.write(f"  {kw}: {hits[:8]}\n")
out.close(); print("ok")
