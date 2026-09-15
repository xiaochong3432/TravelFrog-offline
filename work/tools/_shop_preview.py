from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
d = str(PROJECT_ROOT) + "/work/spec"
out = open(str(PROJECT_ROOT) + "/work/build/shop_preview.txt", "w", encoding="utf-8")
for f in ["eab_shopData_json", "eab_Item_json", "eab_Specialty_json", "eab_Collection_json", "eab_Prize_json"]:
    p = os.path.join(d, f)
    obj = json.load(open(p, encoding="utf-8"))
    out.write(f"===== {f}  type={type(obj).__name__} n={len(obj)}\n")
    items = obj if isinstance(obj, list) else list(obj.values())
    for e in items[:6]:
        out.write(f"  {json.dumps(e, ensure_ascii=False)}\n")
    out.write("\n")
out.close()
print("written")
