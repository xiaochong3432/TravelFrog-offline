from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
out = open(str(PROJECT_ROOT) + "/work/build/origin_map.txt", "w", encoding="utf-8")
origin = json.load(open(os.path.join(D, "origin.json"), encoding="utf-8"))
out.write("=== origin table (all) ===\n")
for k, v in sorted(origin.items()):
    out.write(f"  {k:22s} -> {v}\n")
out.close()
print("written")
