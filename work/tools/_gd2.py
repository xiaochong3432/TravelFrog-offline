from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
g = json.load(open(str(PROJECT_ROOT) + "/work/run/engine/data/gamedata.json", encoding="utf-8"))
print("keys:", list(g.keys()))
print("tables:", len(g["tables"]))
print("items:", len(g["items"]))
print("Item table entries:", len(g["tables"]["Item"]))
print("sample item:", json.dumps(g["tables"]["Item"][0], ensure_ascii=False))
