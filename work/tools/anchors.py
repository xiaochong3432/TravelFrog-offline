#!/usr/bin/env python3
"""Print the char offset of each anchor substring (for spec citations)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

ANCHORS = [
    "h.element=4",
    "挂兜(",
    "pgb.setItems([{value:2",
    "using:1==this.data.replaceSelection",
    'TumblerData=i("tumblerData")',
    'CompostData=t("compostData")',
    "s[r.id]&&(h.clover_id=r.id",
    "for(var o=0,n=this.itemGrids.length",
    "CompostView=function",
    "TumblerLoader=function",
    "TumblerToy=function",
    "prototype.updateSelect=function",
    "prototype.openBuyTips=function",
    "this.itemGrids=[this.itemGrid0",
    "prototype.update=function(){var e=this.getModel(FurnitureModel).compostData",
    "FurnitureShopController=function",
    "prototype.item_load_shop_info=function",
    "prototype.updateDecoration=function",
    "prototype.updateFurniture=function",
    "prototype.getReplaced=function",
    "FurnitureCargoPage=function",
    "FurnitureBenchView=function",
    "prototype.onSelectGroupChange=function",
    "getHouseItemsByType(Tabikaeru.DataType.ItemType.FURNITURE_TOOL)",
    "getHouseItemsByType(Tabikaeru.DataType.ItemType.Courtyard,1)",
    "prototype.updateRedot=function(){if(this.isOpen())",
    "prototype.isLockBench=function",
    "prototype.getMateList=function",
    "e[e.CLOVER=2e5]",
    "e[e.GoTravel=1]",
    "case TimerEvent.Type.FurnitureFinish",
    "case TimerEvent.Type.Decoration",
    "btnPot1.addEventListener",
    "prototype.on_compost_tap=function",
    "prototype.onItemTap=function(e){var t=this,i=e.item;i&&core.PageManage",
    "prototype.onItemTap=function(e){var t,i=e.item;i&&core.PageManage",
    "prototype.update=function(){var e={},t=Tabikaeru.DataManager.instance().CompostData.all()",
    "prototype.addHouseItem=function(e,t,i)",
    "prototype.doAddHouseItem=function",
]
for s in ANCHORS:
    print(f"{d.find(s):>8}  {s[:78]}")
