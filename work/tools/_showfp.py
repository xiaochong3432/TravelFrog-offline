from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
d = json.load(open(str(PROJECT_ROOT) + "/work/run/engine/data/define.json", encoding="utf-8"))
m = d["maps"]
print("maps now:", sorted(m.keys()))
if "Frogpattern" in m:
    for k in sorted(m["Frogpattern"]):
        print(f"  pattern {k}: {m['Frogpattern'][k]}")
print("FrogMotionNum:", m.get("FrogMotionNum"))
