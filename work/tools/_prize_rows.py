from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, collections
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
prize = json.load(open(D+r"\Prize.json", encoding="utf-8"))
items = {i["id"]: i for i in json.load(open(D+r"\Item.json", encoding="utf-8"))}
out = open(str(PROJECT_ROOT) + "/work/build/prize_rows.txt","w",encoding="utf-8")
out.write(f"Prize rows: {len(prize)}\n")
out.write(f"stock values: {dict(collections.Counter(str(p.get('stock')) for p in prize))}\n")
out.write("by rank:\n")
byr = collections.defaultdict(list)
for p in prize: byr[p.get("rank")].append(p)
for r in sorted(byr):
    out.write(f"  rank {r} ({len(byr[r])} rows): {[ (p['id'], p['itemId'], p['stock']) for p in byr[r] ]}\n")
out.write("\nrows with itemId < 0: %s\n" % [(p['id'], p['rank'], p['itemId']) for p in prize if p.get('itemId',0) < 0])
out.write("all itemIds exist in Item.json: %s\n" % all(p.get('itemId',-1) < 0 or p['itemId'] in items for p in prize))
out.close(); print("ok")
