#!/usr/bin/env python3
"""Build run/web/map_data.json from the game's OWN tables.

The 地图 page needs, per province: the display name, the flower art the game already ships
(`visitor_flower_N`) and the sign art (`visitor_sign_N`). All of it comes out of
visitors.provinceList -- nothing is invented here, and no national boundary is drawn by us
(a hand-drawn China outline would be both inaccurate and, for a Chinese release, improper:
published maps must be the standard ones with a 审图号).

Also lists which provinces host one of the museums, taken from museumData.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os

ROOT = str(PROJECT_ROOT)
GD = json.load(open(os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json"),
                    encoding="utf-8"))
T = GD["tables"]

# which image files actually exist, so the page never asks for a 404
present = set()
for dp, dn, fn in os.walk(os.path.join(ROOT, "work", "run", "web", "resource", "China")):
    for f in fn:
        present.add(f.lower())


def art(index):
    if not index:
        return None
    return index + ".png" if (index + ".png").lower() in present else None


provs = T["visitors"]["provinceList"]
museum_prov = {}
for key, row in (T.get("museumData") or {}).items():
    name = row.get("name") or ""
    for prov in provs:
        if prov and prov in name:
            museum_prov[prov] = name
            break
    else:
        # 江西省博物馆 -> 江西 etc. (match on the province prefix)
        for prov in provs:
            if prov and name.startswith(prov):
                museum_prov[prov] = name
                break

# museumData names 南越王博物院 / 吴文化博物馆, which do not contain their province, so
# spell those two out (they are in 广东 / 江苏).
for museum_name, prov in (("南越王", "广东"), ("吴文化", "江苏")):
    for key, row in (T.get("museumData") or {}).items():
        if museum_name in (row.get("name") or ""):
            museum_prov[prov] = row.get("name")

out = {
    "source": "visitors.provinceList / museumData (游戏自带表)",
    "provinces": [],
    "museumProvinces": museum_prov,
}
for key in sorted(provs, key=lambda k: (provs[k].get("ID") or 0, k)):
    row = provs[key]
    out["provinces"].append({
        "province": row.get("Province") or key,
        "name": row.get("DisplayName") or key,
        "flower": art(row.get("FlowerIcon")),
        "flowerName": row.get("FlowerName") or "",
        "sign": art(row.get("Icon")),
        "id": row.get("ID") or 0,
    })

dest = os.path.join(ROOT, "work", "run", "web", "map_data.json")
io.open(dest, "w", encoding="utf-8").write(json.dumps(out, ensure_ascii=False, indent=1))
print("wrote %s : %d provinces, %d with a museum, %d flower arts"
      % (dest, len(out["provinces"]), len(museum_prov),
         sum(1 for p in out["provinces"] if p["flower"])))
for p in out["provinces"][:4]:
    print("  ", p["province"], p["name"], p["flower"], p["flowerName"], p["sign"])
