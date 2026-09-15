from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
g = json.load(open(str(PROJECT_ROOT) + "/work/run/engine/data/gamedata.json", encoding="utf8"))
print("top-level keys:", list(g.keys()))
for k, v in g.items():
    if isinstance(v, list):
        print(f"  {k:14s} list[{len(v)}]  sample={v[:4]}")
    elif isinstance(v, dict):
        ks = list(v.keys())
        print(f"  {k:14s} dict[{len(v)}]  sample keys={ks[:6]}")
    else:
        print(f"  {k:14s} {v!r}")
