from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json
d = json.load(open(str(PROJECT_ROOT) + "/work/run/engine/data/define.json", encoding="utf-8"))
print("maps:", list(d["maps"].keys()))
for k in ["PrizeBalls","PrizeClover","PrizeBallName","FRIEND_GIFTPER_NORMAL","FRIEND_GIFTPER_RARE","PICTURE_TOOLS_PLUSPER","Season","WeatherType","HoursType"]:
    if k in d["maps"]:
        print(f"  {k}: {json.dumps(d['maps'][k], ensure_ascii=False)}")
s = d["scalars"]
print("\nkey scalars:")
for k in ["RAFFEL_NEEDTICKETS","SHOP_TICKET_PER","BASE_PICTURE_PER","PICTURE_GETMAX","SPECIALTY_PER","COLLECT_PER","ALBUM_MAX","FRIEND_VISIT_COOLDOWN","FRIEND_VISIT_RNDSEC","FRIEND_VISIT_RNDPER","FRIEND_VISIT_COOL","TRAVEL_TIME_MIN","FROG_RESTTIME","BASE_HP","BAGITEMS","DESKITEMS","TRAVEL_ITEM_GETMAX","ComposeId"]:
    if k in s: print(f"  {k} = {s[k]}")
