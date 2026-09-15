from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os, hashlib
A = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
B = str(PROJECT_ROOT) + "/work/spec/data"
PAIRS = [("Item","item.json"), ("shopData","shopData.json"), ("Specialty","specialty.json"),
         ("Collection","collection.json"), ("Prize","prize.json"), ("Character","Character_json.json"),
         ("GoalNumber","GoalNumber_json.json"), ("Achieve","Achieve_json.json"),
         ("visitors","visitors_json.json"), ("gameplay","gameplay_json.json"),
         ("lotteryData","lotteryData.json"), ("GiftData","giftData.json"),
         ("drawingPageData","drawingPageData_json.json"), ("story","story_json.json"),
         ("Shop","shopTable.json")]
def h(o): return hashlib.sha256(json.dumps(o, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]
out = open(str(PROJECT_ROOT) + "/work/build/xcheck2.txt","w",encoding="utf-8")
for mine, theirs in PAIRS:
    pa, pb = os.path.join(A, mine+".json"), os.path.join(B, theirs)
    if not (os.path.exists(pa) and os.path.exists(pb)):
        out.write(f"{mine:18s} MISSING (a={os.path.exists(pa)} b={os.path.exists(pb)})\n"); continue
    a, b = json.load(open(pa,encoding="utf-8")), json.load(open(pb,encoding="utf-8"))
    la = len(a) if hasattr(a,"__len__") else "?"
    lb = len(b) if hasattr(b,"__len__") else "?"
    out.write(f"{mine:18s} n={la:<5} vs {lb:<5} hash {h(a)} vs {h(b)}  {'MATCH' if h(a)==h(b) else 'DIFFER'}\n")
out.close(); print("ok")
