#!/usr/bin/env python3
"""Two museum provinces whose names do not contain the province (facts, not data):
南越王博物院 is in 广州 (广东), 吴文化博物馆 is in 苏州 (江苏)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

P = str(PROJECT_ROOT) + "/work/tools/build_map_data.py"
src = io.open(P, encoding="utf-8").read()
old = """out = {
    "source": "visitors.provinceList / museumData (游戏自带表)","""
new = """# museumData names 南越王博物院 / 吴文化博物馆, which do not contain their province, so
# spell those two out (they are in 广东 / 江苏).
for museum_name, prov in (("南越王", "广东"), ("吴文化", "江苏")):
    for key, row in (T.get("museumData") or {}).items():
        if museum_name in (row.get("name") or ""):
            museum_prov[prov] = row.get("name")

out = {
    "source": "visitors.provinceList / museumData (游戏自带表)","""
assert src.count(old) == 1
io.open(P, "w", encoding="utf-8").write(src.replace(old, new))
print("museum province mapping completed")
