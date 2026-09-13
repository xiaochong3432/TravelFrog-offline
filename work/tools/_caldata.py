from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
cd = json.load(open(os.path.join(D,"calendarData.json"), encoding="utf-8"))
out = open(str(PROJECT_ROOT) + "/work/build/calendar_data.txt","w",encoding="utf-8")
out.write(f"calendarData keys: {list(cd.keys())}\n\n")
b = cd.get("beginner") or {}
out.write(f"beginner: {len(b)} entries\n")
for k in sorted(b, key=lambda x: int(x))[:8]:
    out.write(f"  {k}: {json.dumps(b[k], ensure_ascii=False)}\n")
m = cd.get("month") or {}
out.write(f"\nmonth: {len(m)} entries; sample {json.dumps(list(m.items())[:3], ensure_ascii=False)}\n")
n = cd.get("note") or {}
out.write(f"\nnote: type={type(n).__name__} n={len(n)}\n")
keys = list(n)[:6] if isinstance(n, dict) else None
if keys:
    for k in keys: out.write(f"  {k}: {json.dumps(n[k], ensure_ascii=False)[:200]}\n")
else:
    out.write(f"  {json.dumps(n, ensure_ascii=False)[:400]}\n")
out.close(); print("ok")
