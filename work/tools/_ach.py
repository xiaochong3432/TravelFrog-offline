from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
ach = json.load(open(os.path.join(D,"Achieve.json"), encoding="utf-8"))
out = open(str(PROJECT_ROOT) + "/work/build/achieve.txt","w",encoding="utf-8")
out.write(f"Achieve rows: {len(ach)}\n")
out.write("keys: %s\n\n" % list(ach[0].keys()))
for a in ach:
    out.write(f"  id={a.get('id'):<4} name={a.get('name')!r:<22} info={a.get('info')!r} special={a.get('is_special')!r}\n")
out.close(); print("ok")
